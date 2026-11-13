defmodule PuppyLog.Daily.Changes.LinkRoutine do
  @moduledoc """
  Links an event to the routine occurrence it fulfils.

  The `routine` argument chooses the occurrence:
    * `"auto"`: the closest candidate on the event's local day within the
      tolerance (the day is planned first), if any,
    * `"none"`: no occurrence,
    * an occurrence id: that occurrence, on any day, as long as the event can
      fulfil it; otherwise the action fails with an error on `:routine`.

  An open occurrence is completed with `done_at = occurred_at`. A non-potty
  occurrence that was already ticked off by hand keeps its recorded time and
  only gets the `event_id`.

  On update and destroy the previous link is released first: an occurrence
  the event completed is reopened, one it was only attached to keeps its tick
  and loses the `event_id`. While choosing, occurrences linked to the event
  itself count as free.

  The choice is validated inside the transaction (reads only); all occurrence
  writes happen after the event is committed, so a failing link never loses
  the user's entry. If the chosen occurrence was completed concurrently
  („Schon erledigt“) the event simply stays unlinked.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias PuppyLog.{Clock, Daily}
  alias PuppyLog.Daily.{Matching, Occurrence}

  @target :link_routine_target
  @invalid "passt nicht zu diesem Eintrag"

  @impl true
  def change(%{action_type: :destroy} = changeset, _opts, _context) do
    Ash.Changeset.after_transaction(changeset, &unlink_destroyed/2)
  end

  def change(changeset, _opts, _context) do
    changeset
    |> Ash.Changeset.before_transaction(&plan_day/1)
    |> Ash.Changeset.before_action(&choose/1)
    |> Ash.Changeset.after_transaction(&link/2)
  end

  @doc """
  The occurrences (of one day) an event could fulfil: `auto` is the automatic
  match or `nil`, `candidates` are sorted closest first. Occurrences linked to
  `event_id` count as free.
  """
  @spec choices([Occurrence.t()], map, NaiveDateTime.t(), Ecto.UUID.t() | nil) ::
          %{auto: Occurrence.t() | nil, candidates: [Occurrence.t()]}
  def choices(occurrences, event, actual, event_id \\ nil) do
    by_id = Map.new(occurrences, &{&1.id, &1})
    free = Enum.map(occurrences, &as_free(&1, event_id))
    original = fn occurrence -> occurrence && Map.fetch!(by_id, occurrence.id) end

    %{
      auto: original.(Matching.auto_match(free, event, actual)),
      candidates: Enum.map(Matching.candidates(free, event, actual), original)
    }
  end

  @doc "The local day of an event time."
  @spec local_date(DateTime.t()) :: Date.t()
  def local_date(occurred_at), do: occurred_at |> Clock.local() |> DateTime.to_date()

  # Matching only considers open occurrences.
  defp as_free(occurrence, event_id) do
    if free?(occurrence, event_id), do: %{occurrence | status: :open}, else: occurrence
  end

  defp free?(%{status: :open}, _event_id), do: true
  defp free?(%{event_id: id}, event_id) when not is_nil(id) and id == event_id, do: true
  defp free?(occurrence, _event_id), do: ticked_by_hand?(occurrence)

  defp ticked_by_hand?(%{status: :done, event_id: nil, kind: kind}), do: kind != :potty
  defp ticked_by_hand?(_occurrence), do: false

  # -- before the transaction: plan the day for the automatic match

  defp plan_day(changeset) do
    with "auto" <- Ash.Changeset.get_argument(changeset, :routine),
         %DateTime{} = occurred_at <- Ash.Changeset.get_attribute(changeset, :occurred_at) do
      :ok = Daily.ensure_day(local_date(occurred_at))
    end

    changeset
  end

  # -- inside the transaction: choose (read only)

  defp choose(changeset) do
    case Ash.Changeset.get_argument(changeset, :routine) do
      "none" -> put_target(changeset, nil)
      "auto" -> put_target(changeset, auto_target(changeset))
      id -> explicit_target(changeset, id)
    end
  end

  defp auto_target(changeset) do
    occurred_at = Ash.Changeset.get_attribute(changeset, :occurred_at)
    local = Clock.local(occurred_at)

    occurrences =
      Occurrence
      |> Ash.Query.for_read(:on_date, %{date: DateTime.to_date(local)})
      |> Ash.read!(authorize?: false)

    case choices(occurrences, event(changeset), DateTime.to_naive(local), event_id(changeset)) do
      %{auto: nil} -> nil
      %{auto: occurrence} -> occurrence.id
    end
  end

  defp explicit_target(changeset, id) do
    with {:ok, occurrence} <- Ash.get(Occurrence, id, authorize?: false),
         true <- free?(occurrence, event_id(changeset)),
         true <- Matching.fulfils?(occurrence.kind, event(changeset)) do
      put_target(changeset, occurrence.id)
    else
      _ -> Ash.Changeset.add_error(changeset, field: :routine, message: @invalid)
    end
  end

  defp put_target(changeset, target),
    do: Ash.Changeset.set_context(changeset, %{@target => target})

  defp event(changeset) do
    %{
      kind: Ash.Changeset.get_attribute(changeset, :kind),
      location: Ash.Changeset.get_attribute(changeset, :location)
    }
  end

  defp event_id(changeset), do: Ash.Changeset.get_attribute(changeset, :id)

  # -- after the transaction: write the occurrences

  defp link(changeset, {:ok, event}) do
    actor = changeset.context[:private][:actor]

    with :ok <- release(event.id, changeset.data.occurred_at),
         :ok <- fulfil(changeset.context[@target], event, actor) do
      {:ok, event}
    end
  end

  defp link(_changeset, result), do: result

  defp unlink_destroyed(_changeset, {:ok, event} = result) do
    with :ok <- release(event.id, event.occurred_at) do
      result
    end
  end

  defp unlink_destroyed(_changeset, result), do: result

  defp release(event_id, occurred_at) do
    Occurrence
    |> Ash.Query.filter(event_id == ^event_id)
    |> Ash.read!(authorize?: false)
    |> Enum.reduce_while(:ok, fn occurrence, :ok ->
      case release_one(occurrence, occurred_at) do
        {:ok, _occurrence} -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  # Completed by the event (done at the event's time) → open again;
  # ticked by hand and only attached → keep the tick.
  defp release_one(occurrence, occurred_at) do
    if completed_by_event?(occurrence, occurred_at),
      do: reopen(occurrence),
      else: attach(occurrence, nil)
  end

  defp completed_by_event?(%{done_at: %DateTime{} = done_at}, %DateTime{} = occurred_at),
    do: DateTime.compare(done_at, occurred_at) == :eq

  defp completed_by_event?(_occurrence, _occurred_at), do: false

  defp reopen(occurrence), do: Daily.reopen_occurrence(occurrence, authorize?: false)

  defp fulfil(nil, _event, _actor), do: :ok

  defp fulfil(id, event, actor) do
    case Ash.get(Occurrence, id, authorize?: false) do
      {:ok, %{status: :open} = occurrence} ->
        complete(occurrence, event, actor)

      # done or skipped by someone else meanwhile: the event stays unlinked
      {:ok, occurrence} ->
        if ticked_by_hand?(occurrence),
          do: occurrence |> attach(event.id) |> ok(),
          else: :ok

      # deleted meanwhile (e.g. the routine was archived)
      {:error, _error} ->
        :ok
    end
  end

  defp complete(occurrence, event, actor) do
    occurrence
    |> Daily.complete_occurrence(%{done_at: event.occurred_at, event_id: event.id},
      actor: actor,
      authorize?: false
    )
    |> case do
      {:error, error} -> if already_done?(error), do: :ok, else: {:error, error}
      result -> ok(result)
    end
  end

  defp attach(occurrence, event_id) do
    occurrence
    |> Ash.Changeset.for_update(:attach_event, %{event_id: event_id})
    |> Ash.update(authorize?: false)
  end

  defp ok({:ok, _record}), do: :ok
  defp ok({:error, _error} = error), do: error

  defp already_done?(%{errors: errors}) when is_list(errors),
    do: Enum.any?(errors, &already_done?/1)

  defp already_done?(%{field: :status, message: "Schon erledigt"}), do: true
  defp already_done?(_error), do: false
end
