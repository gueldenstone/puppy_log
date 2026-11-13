defmodule PuppyLog.Daily.Reminders do
  @moduledoc """
  Sends routine reminders and follow-ups by Web Push, once a minute.

    * Reminder: `remind?` is on, the occurrence is open, nobody was reminded
      yet and now lies within `[planned_start, planned_start + 10 min]`.
    * Follow-up: `follow_up_minutes` is set, the reminder went out, the
      occurrence is still open and now lies within
      `[planned_start + follow_up_minutes, … + 10 min]`.
    * Quiet hours suppress both. A suppressed message is not caught up
      later: once the 10 minutes are over it is dropped.

  `reminded_at` / `follow_up_sent_at` are claimed (set only while still nil)
  before anything is sent, so concurrent ticks or a restart can never send
  the same message twice. A reopened occurrence keeps them and is therefore
  not reminded again.

  The process ticks at every full minute. A failing tick is logged and the
  next minute is tried again. It is only started with
  `config :puppy_log, PuppyLog.Daily.Reminders, enabled: true`.
  """

  use GenServer

  require Ash.Query
  require Logger

  alias PuppyLog.{Clock, Daily}
  alias PuppyLog.Daily.{Notify, Occurrence, Settings}

  @late_minutes 10

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Whether the reminder process should run (see moduledoc)."
  @spec enabled?() :: boolean
  def enabled? do
    :puppy_log |> Application.get_env(__MODULE__, []) |> Keyword.get(:enabled, false)
  end

  @doc """
  Plans today and sends every reminder and follow-up due at `now`. Also
  looks at yesterday, for routines shortly before midnight.
  """
  @spec tick(DateTime.t()) :: :ok
  def tick(%DateTime{} = now) do
    local = Clock.local(now)
    today = DateTime.to_date(local)
    :ok = Daily.ensure_day(today)
    settings = Daily.settings(authorize?: false)

    unless quiet?(settings, DateTime.to_time(local)) do
      today
      |> open_occurrences()
      |> Enum.each(&send_due(&1, now))
    end

    :ok
  end

  @doc "Whether `time` lies in the quiet hours (`quiet_until` exclusive)."
  @spec quiet?(Settings.t(), Time.t()) :: boolean
  def quiet?(%Settings{quiet_hours_enabled: false}, _time), do: false

  def quiet?(%Settings{quiet_from: from, quiet_until: until}, time) do
    after_from? = Time.compare(time, from) != :lt
    before_until? = Time.compare(time, until) == :lt

    case Time.compare(from, until) do
      :lt -> after_from? and before_until?
      :gt -> after_from? or before_until?
      :eq -> false
    end
  end

  defp open_occurrences(today) do
    yesterday = Date.add(today, -1)

    Occurrence
    |> Ash.Query.filter(
      date in [^yesterday, ^today] and status == :open and remind? == true and
        (is_nil(reminded_at) or (not is_nil(follow_up_minutes) and is_nil(follow_up_sent_at)))
    )
    |> Ash.read!(authorize?: false)
  end

  defp send_due(occurrence, now) do
    start = Clock.local_datetime(occurrence.date, occurrence.planned_start)

    cond do
      is_nil(occurrence.reminded_at) and due?(now, start) ->
        claim_and_send(occurrence, :mark_reminded, :reminded_at, now, &Notify.reminder/1)

      not is_nil(occurrence.reminded_at) and not is_nil(occurrence.follow_up_minutes) and
          due?(now, DateTime.add(start, occurrence.follow_up_minutes, :minute)) ->
        claim_and_send(
          occurrence,
          :mark_follow_up_sent,
          :follow_up_sent_at,
          now,
          &Notify.follow_up/1
        )

      true ->
        :skip
    end
  end

  defp due?(now, at) do
    DateTime.compare(now, at) != :lt and
      DateTime.compare(now, DateTime.add(at, @late_minutes, :minute)) != :gt
  end

  # Sets the timestamp only while it is still nil and the occurrence still
  # open; only the caller that changed the row sends.
  defp claim_and_send(occurrence, action, field, now, payload) do
    id = occurrence.id

    result =
      Occurrence
      |> Ash.Query.filter(id == ^id and status == :open and is_nil(^Ash.Expr.ref(field)))
      |> Ash.bulk_update!(action, %{at: now},
        authorize?: false,
        strategy: :atomic,
        return_records?: true
      )

    case result.records do
      [claimed] -> Notify.to_recipients(payload.(claimed))
      [] -> :skip
    end
  end

  # -- GenServer

  @impl true
  def init(_opts), do: {:ok, schedule()}

  @impl true
  def handle_info(:tick, _timer) do
    try do
      tick(Clock.now())
    catch
      kind, reason ->
        Logger.error("Reminder tick failed: " <> Exception.format(kind, reason, __STACKTRACE__))
    end

    {:noreply, schedule()}
  end

  # State: the reference of the timer for the next tick.
  defp schedule do
    ms = 60_000 - rem(System.system_time(:millisecond), 60_000)
    Process.send_after(self(), :tick, ms)
  end
end
