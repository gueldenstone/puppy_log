defmodule PuppyLog.Daily.Notify do
  @moduledoc """
  Push texts for routine occurrences and who receives them.

  Every push about an occurrence carries the tag `routine-<id>`, so a later
  message (follow-up, done, skipped) replaces the earlier one on the phone.

  A tap on a push opens the occurrence's sheet (`/routine/<id>`).

  `after_outcome/2` tells the other members when an occurrence they were
  reminded about is done or skipped, unless it is quiet hours or the
  occurrence lies before yesterday (a late correction). It runs in a task under
  `PuppyLog.TaskSupervisor`, or inline when configured with
  `config :puppy_log, PuppyLog.Daily.Notify, async: false` (tests).
  """

  require Ash.Query

  alias PuppyLog.Accounts.User
  alias PuppyLog.{Clock, Daily, Notifications}
  alias PuppyLog.Daily.{Occurrence, Reminders}

  @doc "Ids of the members who receive routine pushes."
  @spec recipient_ids() :: [Ecto.UUID.t()]
  def recipient_ids do
    User
    |> Ash.Query.filter(receives_reminders == true)
    |> Ash.Query.select([:id])
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.id)
  end

  @doc "Sends `payload` to all recipients."
  @spec to_recipients(map) :: [PuppyLog.Notifications.Push.result()]
  def to_recipients(payload), do: Notifications.deliver_to_users(recipient_ids(), payload)

  @doc "Reminder at the planned time."
  @spec reminder(Occurrence.t()) :: map
  def reminder(%Occurrence{planned_end: nil} = occurrence),
    do: payload(occurrence, occurrence.name, "Jetzt fällig (#{hh_mm(occurrence.planned_start)}).")

  def reminder(%Occurrence{} = occurrence) do
    payload(
      occurrence,
      occurrence.name,
      "Zwischen #{hh_mm(occurrence.planned_start)} und #{hh_mm(occurrence.planned_end)}."
    )
  end

  @doc """
  Follow-up while the occurrence is still open. It goes out
  `follow_up_minutes` after the occurrence became due (the end of a window,
  otherwise the planned time), so that is how long it has been due.
  """
  @spec follow_up(Occurrence.t()) :: map
  def follow_up(%Occurrence{} = occurrence) do
    payload(
      occurrence,
      "#{occurrence.name} noch offen",
      "Seit #{occurrence.follow_up_minutes} Minuten fällig."
    )
  end

  @doc """
  After `:complete` / `:skip`: if the members were reminded, tells everyone
  but `actor` who did it. Nothing is sent during quiet hours or for an
  occurrence before yesterday.
  """
  @spec after_outcome(Occurrence.t(), User.t() | nil) :: :ok
  def after_outcome(%Occurrence{reminded_at: nil}, _actor), do: :ok

  def after_outcome(%Occurrence{} = occurrence, actor) do
    now = Clock.now()

    if recent?(occurrence, now) and not quiet?(now) do
      run(fn -> send_outcome(occurrence, actor) end)
    end

    :ok
  end

  defp recent?(occurrence, now),
    do: Date.compare(occurrence.date, Date.add(DateTime.to_date(now), -1)) != :lt

  defp quiet?(now),
    do: Reminders.quiet?(Daily.settings(authorize?: false), DateTime.to_time(now))

  defp send_outcome(occurrence, actor) do
    actor_id = actor && actor.id

    recipient_ids()
    |> Enum.reject(&(&1 == actor_id))
    |> Notifications.deliver_to_users(outcome(occurrence, who(actor)))
  end

  defp outcome(%Occurrence{status: :done} = occurrence, who) do
    done_at = occurrence.done_at |> Clock.local() |> DateTime.to_time()
    payload(occurrence, "#{occurrence.name} erledigt ✓", "#{who}, #{hh_mm(done_at)}")
  end

  defp outcome(%Occurrence{status: :skipped} = occurrence, who),
    do: payload(occurrence, "#{occurrence.name} übersprungen", who)

  defp who(nil), do: "Jemand"
  defp who(%{name: name}) when is_binary(name) and name != "", do: name
  defp who(%{email: email}), do: to_string(email)

  defp run(fun) do
    if async?() do
      {:ok, _pid} = Task.Supervisor.start_child(PuppyLog.TaskSupervisor, fun)
    else
      fun.()
    end

    :ok
  end

  defp async? do
    :puppy_log |> Application.get_env(__MODULE__, []) |> Keyword.get(:async, true)
  end

  defp payload(occurrence, title, body) do
    %{
      title: title,
      body: body,
      tag: "routine-#{occurrence.id}",
      url: "/routine/#{occurrence.id}"
    }
  end

  defp hh_mm(%Time{} = time), do: Calendar.strftime(time, "%H:%M")
end
