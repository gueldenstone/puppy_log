defmodule PuppyLog.Daily.Planner do
  @moduledoc """
  Turns routines into occurrences for concrete days.

  A routine is planned on `date` when
    * the puppy has arrived (`date >= arrival_date`; no arrival date → nothing),
    * `date` is one of its weekdays,
    * it existed on `date`: created before that day, or created during it with
      `starts_at` still ahead of the (local) creation time,
    * it was not archived on or before `date`.

  Planning never changes existing occurrences. Only routine edits touch
  today's still-open occurrence (`replan_today/1`); past days never change.
  Runs internally with `authorize?: false`.
  """

  require Ash.Query

  alias PuppyLog.Clock
  alias PuppyLog.Daily.{Occurrence, Routine}

  @doc "Plans all routines due on `date`."
  @spec ensure_day(Date.t(), keyword) :: :ok
  def ensure_day(%Date{} = date, _opts \\ []) do
    case arrival_date() do
      nil -> :ok
      arrival -> plan(Date.range(date, date), arrival)
    end
  end

  @doc "Plans all days of `first..last`, clipped to `arrival_date..today`."
  @spec ensure_days(Date.t(), Date.t(), keyword) :: :ok
  def ensure_days(%Date{} = first, %Date{} = last, _opts \\ []) do
    with arrival when not is_nil(arrival) <- arrival_date(),
         first = Enum.max([first, arrival], Date),
         last = Enum.min([last, Clock.today()], Date),
         true <- Date.compare(first, last) != :gt do
      plan(Date.range(first, last), arrival)
    else
      _ -> :ok
    end
  end

  @doc """
  Brings today's occurrence of `routine` in line with the routine after an
  edit or archiving: an open occurrence gets the new snapshot or is removed if
  the routine no longer applies today; a missing one is planned. Done and
  skipped occurrences stay as they are.
  """
  @spec replan_today(Routine.t()) :: :ok
  def replan_today(%Routine{} = routine) do
    today = Clock.today()
    arrival = arrival_date()
    planned? = not is_nil(arrival) and plannable?(routine, today, arrival)

    case {today_occurrence(routine, today), planned?} do
      {nil, true} ->
        create_all([snapshot(routine, today)])

      {%Occurrence{status: :open} = occurrence, true} ->
        occurrence
        |> Ash.Changeset.for_update(
          :replan,
          Map.drop(snapshot(routine, today), [:routine_id, :date])
        )
        |> Ash.update!(authorize?: false)

        :ok

      {%Occurrence{status: :open} = occurrence, false} ->
        Ash.destroy!(occurrence, authorize?: false)

      _ ->
        :ok
    end
  end

  defp plan(range, arrival) do
    {first_start, _} = Clock.day_bounds(range.first)
    {_, last_end} = Clock.day_bounds(range.last)

    routines =
      Routine
      |> Ash.Query.filter(
        inserted_at < ^last_end and (is_nil(archived_at) or archived_at >= ^first_start)
      )
      |> Ash.read!(authorize?: false)

    existing =
      Occurrence
      |> Ash.Query.filter(date >= ^range.first and date <= ^range.last)
      |> Ash.Query.select([:routine_id, :date])
      |> Ash.read!(authorize?: false)
      |> MapSet.new(&{&1.routine_id, &1.date})

    for date <- range,
        routine <- routines,
        not MapSet.member?(existing, {routine.id, date}),
        plannable?(routine, date, arrival) do
      snapshot(routine, date)
    end
    |> create_all()
  end

  defp create_all([]), do: :ok

  defp create_all(inputs) do
    # Upsert on [:routine_id, :date] without changing any field, so a
    # concurrent planner run cannot fail or overwrite an outcome.
    case Ash.bulk_create(inputs, Occurrence, :plan,
           authorize?: false,
           notify?: true,
           return_errors?: true,
           stop_on_error?: true
         ) do
      %Ash.BulkResult{status: :success} -> :ok
      %Ash.BulkResult{errors: errors} -> raise Ash.Error.to_error_class(errors)
    end
  end

  defp plannable?(routine, date, arrival) do
    Date.compare(date, arrival) != :lt and
      Date.day_of_week(date) in routine.weekdays and
      exists_on?(routine, date) and
      not archived_by?(routine, date)
  end

  defp exists_on?(routine, date) do
    created = Clock.local(routine.inserted_at)

    case Date.compare(DateTime.to_date(created), date) do
      :lt -> true
      :eq -> Time.compare(routine.starts_at, DateTime.to_time(created)) == :gt
      :gt -> false
    end
  end

  defp archived_by?(%{archived_at: nil}, _date), do: false

  defp archived_by?(%{archived_at: archived_at}, date),
    do: Date.compare(archived_at |> Clock.local() |> DateTime.to_date(), date) != :gt

  defp arrival_date do
    case PuppyLog.Puppy.get_profile!(authorize?: false) do
      %{arrival_date: arrival} -> arrival
      nil -> nil
    end
  end

  defp today_occurrence(routine, today) do
    Occurrence
    |> Ash.Query.filter(routine_id == ^routine.id and date == ^today)
    |> Ash.read_one!(authorize?: false)
  end

  defp snapshot(routine, date) do
    %{
      routine_id: routine.id,
      date: date,
      name: routine.name,
      kind: routine.kind,
      planned_start: routine.starts_at,
      planned_end: routine.ends_at,
      assignee_id: routine.assignee_id,
      remind?: routine.remind?,
      follow_up_minutes: routine.follow_up_minutes
    }
  end
end
