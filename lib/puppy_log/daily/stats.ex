defmodule PuppyLog.Daily.Stats do
  @moduledoc """
  Statistics for the history screen: how well the routines were kept and how
  house training goes, over a rolling period ending today.

  An occurrence counts when it is done or was missed (still open on a past
  day); today's open and all skipped occurrences are left out. It is kept when
  it is done within the tolerance (`Matching.kept?/1`).

  All data of the period and the period before it is read once and aggregated
  here; the result holds only plain maps.
  """

  require Ash.Query

  alias PuppyLog.{Clock, Daily}
  alias PuppyLog.Daily.{Matching, Occurrence}

  @periods [
    {"1w", "1 Woche"},
    {"2w", "2 Wochen"},
    {"4w", "4 Wochen"},
    {"2m", "2 Monate"},
    {"4m", "4 Monate"},
    {"6m", "6 Monate"},
    {"1y", "1 Jahr"}
  ]

  @lengths %{
    "1w" => {:week, 1},
    "2w" => {:week, 2},
    "4w" => {:week, 4},
    "2m" => {:month, 2},
    "4m" => {:month, 4},
    "6m" => {:month, 6},
    "1y" => {:month, 12}
  }

  @max_daily_buckets 28
  @weekdays ~w(Mo Di Mi Do Fr Sa So)

  @doc "The selectable periods as `{key, label}`."
  def periods, do: @periods

  @doc "The days of the period `key`, ending `today`."
  @spec range(String.t(), Date.t()) :: Date.Range.t()
  def range(key, today) do
    first =
      case Map.fetch!(@lengths, key) do
        {:week, n} -> Date.add(today, -7 * n + 1)
        {:month, n} -> today |> Date.shift(month: -n) |> Date.add(1)
      end

    Date.range(first, today)
  end

  @doc """
  Statistics of the period `key`. Options: `actor:`, `today:` (default
  `Clock.today/0`).
  """
  def compute(key, opts) do
    today = Keyword.get_lazy(opts, :today, &Clock.today/0)
    read_opts = Keyword.take(opts, [:actor])
    period = range(key, today)

    case PuppyLog.Puppy.get_profile!(authorize?: false) do
      %{arrival_date: %Date{} = arrival} ->
        if Date.compare(arrival, today) == :gt,
          do: empty(period),
          else: compute(period, arrival, today, read_opts)

      _no_arrival ->
        empty(period)
    end
  end

  defp compute(period, arrival, today, read_opts) do
    range = clip(period, arrival)
    previous = previous_range(period, arrival)
    first = if previous, do: previous.first, else: range.first

    :ok = Daily.ensure_days(first, range.last)

    occurrences =
      first
      |> read_occurrences(range.last, read_opts)
      |> Enum.filter(&(&1.date in range))

    {events, previous_events} =
      first
      |> Daily.list_events_between!(range.last, read_opts)
      |> Enum.split_with(&(local_date(&1) in range))

    # Open occurrences before this moment are missed.
    start_of_today = NaiveDateTime.new!(today, ~T[00:00:00])
    counted = Enum.flat_map(occurrences, &outcome(&1, start_of_today))

    totals(counted)
    |> Map.merge(%{
      range: range,
      previous_range: previous,
      buckets: buckets(period, range, counted, today),
      accidents: accidents(events),
      previous_accidents: if(previous, do: accidents(previous_events)),
      pee: by_location(events, :pee),
      poo: by_location(events, :poo),
      nothing: Enum.count(events, &(&1.kind == :potty and &1.nothing)),
      routines: routines(occurrences, start_of_today)
    })
  end

  defp empty(period) do
    %{
      range: period,
      previous_range: nil,
      buckets: [],
      rate: nil,
      kept: 0,
      counted: 0,
      accidents: 0,
      previous_accidents: nil,
      pee: %{outside: 0, inside: 0},
      poo: %{outside: 0, inside: 0},
      nothing: 0,
      routines: []
    }
  end

  defp clip(range, arrival), do: Date.range(Enum.max([range.first, arrival], Date), range.last)

  # The same number of days directly before `period`, clipped to arrival;
  # nil when the puppy had not arrived yet.
  defp previous_range(period, arrival) do
    last = Date.add(period.first, -1)
    first = Date.add(period.first, -Enum.count(period))

    if Date.compare(last, arrival) == :lt, do: nil, else: clip(Date.range(first, last), arrival)
  end

  defp read_occurrences(first, last, read_opts) do
    Occurrence
    |> Ash.Query.filter(date >= ^first and date <= ^last)
    |> Ash.Query.select([
      :routine_id,
      :date,
      :name,
      :status,
      :deviation_minutes,
      :planned_start,
      :planned_end
    ])
    |> Ash.read!(read_opts)
  end

  defp local_date(event), do: event.occurred_at |> Clock.local() |> DateTime.to_date()

  # `[{date, kept?}]` for a counted occurrence, `[]` otherwise.
  defp outcome(occurrence, start_of_today) do
    case Matching.state(occurrence, start_of_today) do
      :done -> [{occurrence.date, Matching.kept?(occurrence.deviation_minutes)}]
      :missed -> [{occurrence.date, false}]
      _ -> []
    end
  end

  defp totals(outcomes) do
    kept = Enum.count(outcomes, fn {_date, kept?} -> kept? end)
    counted = length(outcomes)
    %{kept: kept, counted: counted, rate: rate(kept, counted)}
  end

  defp rate(_kept, 0), do: nil
  defp rate(kept, counted), do: round(kept / counted * 100)

  defp buckets(period, range, outcomes, today) do
    by_date = Enum.group_by(outcomes, fn {date, _kept?} -> date end)

    period
    |> bucket_ranges(range)
    |> Enum.map(fn {label, first, last} ->
      Date.range(first, last)
      |> Enum.flat_map(&Map.get(by_date, &1, []))
      |> totals()
      |> Map.merge(%{
        label: label,
        first: first,
        last: last,
        today?: today in Date.range(first, last)
      })
    end)
  end

  defp bucket_ranges(period, range) do
    cond do
      Enum.count(period) > @max_daily_buckets ->
        range
        |> Enum.chunk_by(&Date.beginning_of_week/1)
        |> Enum.map(fn [first | _] = days ->
          {_year, week} = :calendar.iso_week_number(Date.to_erl(first))
          {"KW #{week}", first, List.last(days)}
        end)

      Enum.count(period) <= 7 ->
        Enum.map(range, &{Enum.at(@weekdays, Date.day_of_week(&1) - 1), &1, &1})

      true ->
        Enum.map(range, &{Calendar.strftime(&1, "%d.%m."), &1, &1})
    end
  end

  defp accidents(events), do: Enum.count(events, &(&1.kind == :potty and &1.location == :inside))

  defp by_location(events, flag) do
    potty = Enum.filter(events, &(&1.kind == :potty and Map.fetch!(&1, flag)))

    %{
      outside: Enum.count(potty, &(&1.location == :outside)),
      inside: Enum.count(potty, &(&1.location == :inside))
    }
  end

  defp routines(occurrences, start_of_today) do
    occurrences
    |> Enum.group_by(& &1.routine_id)
    |> Enum.map(fn {routine_id, group} -> routine_stats(routine_id, group, start_of_today) end)
    |> Enum.sort_by(&{is_nil(&1.rate), &1.rate, &1.name})
  end

  defp routine_stats(routine_id, occurrences, start_of_today) do
    latest = Enum.max_by(occurrences, & &1.date, Date)
    states = Enum.map(occurrences, &Matching.state(&1, start_of_today))

    deviations =
      for %{status: :done, deviation_minutes: deviation} <- occurrences,
          not is_nil(deviation),
          do: deviation

    occurrences
    |> Enum.flat_map(&outcome(&1, start_of_today))
    |> totals()
    |> Map.merge(%{
      routine_id: routine_id,
      name: latest.name,
      skipped: Enum.count(states, &(&1 == :skipped)),
      missed: Enum.count(states, &(&1 == :missed)),
      avg_deviation: if(deviations != [], do: round(Enum.sum(deviations) / length(deviations)))
    })
  end
end
