defmodule PuppyLog.Daily.Matching do
  @moduledoc """
  Pure rules for matching events to planned routine occurrences.

  Works on plain maps or structs with the keys `date`, `planned_start`,
  `planned_end`, `kind` and `status` (occurrences) and `kind` and `location`
  (events).
  """

  @tolerance_minutes 15
  @matching_kinds [:potty, :meal, :walk, :sleep, :play]

  @doc "Tolerance in minutes before and after the planned time or window."
  @spec tolerance_minutes() :: 15
  def tolerance_minutes, do: @tolerance_minutes

  @doc """
  Deviation of `actual` from the planned time (or window) in minutes.

  Negative means early, positive late. Inside a window the deviation is 0,
  otherwise it is the distance to the nearest edge.
  """
  @spec deviation_minutes(Date.t(), Time.t(), Time.t() | nil, NaiveDateTime.t()) :: integer
  def deviation_minutes(date, planned_start, planned_end, actual) do
    start_at = NaiveDateTime.new!(date, planned_start)
    end_at = NaiveDateTime.new!(date, planned_end || planned_start)

    cond do
      NaiveDateTime.compare(actual, start_at) == :lt ->
        -div(NaiveDateTime.diff(start_at, actual, :second), 60)

      NaiveDateTime.compare(actual, end_at) == :gt ->
        div(NaiveDateTime.diff(actual, end_at, :second), 60)

      true ->
        0
    end
  end

  @doc "Whether a deviation is within the tolerance. `nil` is never kept."
  @spec kept?(integer | nil) :: boolean
  def kept?(nil), do: false
  def kept?(deviation), do: abs(deviation) <= @tolerance_minutes

  @doc "Whether an event of the given kind/location can fulfil a routine of `routine_kind`."
  @spec fulfils?(atom, %{kind: atom, location: atom | nil}) :: boolean
  def fulfils?(:potty, %{kind: :potty, location: :outside}), do: true
  def fulfils?(:potty, _event), do: false

  def fulfils?(routine_kind, %{kind: routine_kind}) when routine_kind in @matching_kinds,
    do: true

  def fulfils?(_routine_kind, _event), do: false

  @doc """
  Open occurrences on the day of `actual` that the event can fulfil, closest
  first (ties: earlier planned start first).
  """
  @spec candidates([map], map, NaiveDateTime.t()) :: [map]
  def candidates(occurrences, event, actual) do
    day = NaiveDateTime.to_date(actual)

    occurrences
    |> Enum.filter(&(&1.status == :open and &1.date == day and fulfils?(&1.kind, event)))
    |> Enum.sort_by(
      &{abs(deviation(&1, actual)), Time.to_seconds_after_midnight(&1.planned_start)}
    )
  end

  @doc "The closest candidate if it is within the tolerance, otherwise `nil`."
  @spec auto_match([map], map, NaiveDateTime.t()) :: map | nil
  def auto_match(occurrences, event, actual) do
    case candidates(occurrences, event, actual) do
      [best | _] -> if kept?(deviation(best, actual)), do: best
      [] -> nil
    end
  end

  @doc "Display state of an occurrence at `now`."
  @spec state(map, NaiveDateTime.t()) :: :open | :overdue | :done | :skipped | :missed
  def state(%{status: :open} = occurrence, now) do
    cond do
      Date.compare(occurrence.date, NaiveDateTime.to_date(now)) == :lt ->
        :missed

      NaiveDateTime.compare(now, overdue_after(occurrence)) == :gt ->
        :overdue

      true ->
        :open
    end
  end

  def state(%{status: status}, _now), do: status

  defp deviation(occ, actual),
    do: deviation_minutes(occ.date, occ.planned_start, occ.planned_end, actual)

  defp overdue_after(occ) do
    occ.date
    |> NaiveDateTime.new!(occ.planned_end || occ.planned_start)
    |> NaiveDateTime.add(@tolerance_minutes * 60, :second)
  end
end
