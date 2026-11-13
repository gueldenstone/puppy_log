defmodule PuppyLog.Daily.StatsTest do
  use PuppyLog.DataCase, async: false

  alias PuppyLog.{Clock, Daily}
  alias PuppyLog.Daily.{Occurrence, Stats}

  @today ~D[2026-11-12]

  setup do
    lukas = user_fixture(%{name: "Lukas"})
    pin_local(@today, ~T[20:00:00])

    {:ok, profile} =
      PuppyLog.Puppy.create_profile(%{name: "Fiete", arrival_date: ~D[2026-08-01]},
        actor: lukas
      )

    %{lukas: lukas, profile: profile}
  end

  defp pin_local(date, time), do: pin_clock(Clock.local_datetime(date, time))

  # Created today after its start time, so the planner never plans it: the
  # tests insert exactly the occurrences they need.
  defp routine(actor, name) do
    {:ok, routine} =
      Daily.create_routine(%{name: name, kind: :meal, starts_at: ~T[07:00:00]}, actor: actor)

    routine
  end

  defp occ(routine, date, status, deviation \\ nil, name \\ nil) do
    Ash.Seed.seed!(Occurrence, %{
      routine_id: routine.id,
      date: date,
      name: name || routine.name,
      kind: routine.kind,
      planned_start: routine.starts_at,
      status: status,
      deviation_minutes: deviation
    })
  end

  defp potty(actor, date, attrs) do
    {:ok, event} =
      Daily.log_event(
        Map.merge(
          %{kind: :potty, occurred_at: Clock.local_datetime(date, ~T[10:00:00]), routine: "none"},
          attrs
        ),
        actor: actor
      )

    event
  end

  defp compute(key, actor), do: Stats.compute(key, actor: actor, today: @today)

  test "periods" do
    assert Stats.periods() == [
             {"1w", "1 Woche"},
             {"2w", "2 Wochen"},
             {"4w", "4 Wochen"},
             {"2m", "2 Monate"},
             {"4m", "4 Monate"},
             {"6m", "6 Monate"},
             {"1y", "1 Jahr"}
           ]
  end

  test "ranges end today" do
    assert Stats.range("1w", @today) == Date.range(~D[2026-11-06], @today)
    assert Stats.range("4w", @today) == Date.range(~D[2026-10-16], @today)
    assert Stats.range("2m", @today).first == ~D[2026-09-13]
    assert Stats.range("1y", @today).first == ~D[2025-11-13]
  end

  test "rate excludes skipped and today's open", %{lukas: lukas} do
    breakfast = routine(lukas, "Frühstück")
    occ(breakfast, ~D[2026-11-08], :done, 5)
    occ(breakfast, ~D[2026-11-09], :done, 30)
    occ(breakfast, ~D[2026-11-10], :skipped)
    occ(breakfast, ~D[2026-11-11], :open)
    occ(breakfast, @today, :open)
    # outside the period
    occ(breakfast, ~D[2026-11-01], :done, 0)

    stats = compute("1w", lukas)

    assert %{kept: 1, counted: 3, rate: 33} = stats
    assert stats.range == Date.range(~D[2026-11-06], @today)
    assert stats.previous_range == Date.range(~D[2026-10-30], ~D[2026-11-05])

    assert Enum.map(stats.buckets, & &1.label) == ~w(Fr Sa So Mo Di Mi Do)

    assert %{first: ~D[2026-11-08], last: ~D[2026-11-08], kept: 1, counted: 1, rate: 100} =
             Enum.at(stats.buckets, 2)

    assert %{counted: 0, rate: nil, today?: false} = Enum.at(stats.buckets, 4)
    assert %{counted: 1, kept: 0, rate: 0} = Enum.at(stats.buckets, 5)
    assert %{counted: 0, rate: nil, today?: true} = List.last(stats.buckets)
  end

  test "plans past days that have no occurrences yet", %{lukas: lukas} do
    pin_local(~D[2026-11-09], ~T[06:00:00])
    routine(lukas, "Frühstück")
    pin_local(@today, ~T[20:00:00])

    assert %{kept: 0, counted: 3, rate: 0} = compute("1w", lukas)
    assert [%{date: @today, status: :open}] = Daily.list_occurrences_on!(@today, actor: lukas)
    assert Daily.list_occurrences_on!(Date.add(@today, 1), actor: lukas) == []
  end

  test "4w uses daily buckets, 2m weekly buckets labelled KW", %{lukas: lukas} do
    breakfast = routine(lukas, "Frühstück")
    occ(breakfast, ~D[2026-09-13], :done, 0)
    occ(breakfast, ~D[2026-09-14], :done, 0)
    occ(breakfast, ~D[2026-09-20], :done, 40)
    occ(breakfast, ~D[2026-11-10], :done, 0)

    four_weeks = compute("4w", lukas)
    assert length(four_weeks.buckets) == 28
    assert hd(four_weeks.buckets).label == "16.10."
    assert List.last(four_weeks.buckets).label == "12.11."
    assert Enum.all?(four_weeks.buckets, &(&1.first == &1.last))

    two_months = compute("2m", lukas)
    assert length(two_months.buckets) == 10

    assert [first, second | _] = two_months.buckets

    assert %{
             label: "KW 37",
             first: ~D[2026-09-13],
             last: ~D[2026-09-13],
             kept: 1,
             counted: 1,
             rate: 100,
             today?: false
           } = first

    assert %{label: "KW 38", first: ~D[2026-09-14], last: ~D[2026-09-20], kept: 1, counted: 2} =
             second

    assert %{label: "KW 46", first: ~D[2026-11-09], last: @today, today?: true, rate: 100} =
             List.last(two_months.buckets)

    assert %{kept: 3, counted: 4, rate: 75} = two_months
  end

  test "accidents compare with the previous period", %{lukas: lukas} do
    potty(lukas, ~D[2026-11-06], %{pee: true, poo: true, location: :inside})
    potty(lukas, ~D[2026-11-08], %{pee: true, location: :inside})
    potty(lukas, @today, %{poo: true, location: :inside})
    potty(lukas, ~D[2026-11-09], %{pee: true, location: :outside})
    potty(lukas, ~D[2026-11-10], %{pee: true, poo: true, location: :outside})
    potty(lukas, ~D[2026-11-11], %{nothing: true, location: :outside})

    for day <- 0..5 do
      potty(lukas, Date.add(~D[2026-10-30], day), %{pee: true, location: :inside})
    end

    # before the previous period
    potty(lukas, ~D[2026-10-29], %{pee: true, location: :inside})

    stats = compute("1w", lukas)

    assert %{accidents: 3, previous_accidents: 6, nothing: 1} = stats
    assert stats.pee == %{outside: 2, inside: 2}
    assert stats.poo == %{outside: 1, inside: 2}
  end

  test "per routine stats sorted worst first with average deviation", %{lukas: lukas} do
    walk = routine(lukas, "Gassi")
    occ(walk, ~D[2026-11-09], :done, 10, "Spaziergang")
    occ(walk, ~D[2026-11-10], :done, 14)
    occ(walk, ~D[2026-11-11], :skipped)

    breakfast = routine(lukas, "Frühstück")
    occ(breakfast, ~D[2026-11-10], :done, -3)
    occ(breakfast, ~D[2026-11-11], :open)

    play = routine(lukas, "Spielen")
    occ(play, ~D[2026-11-11], :skipped)

    assert [
             %{
               routine_id: breakfast_id,
               name: "Frühstück",
               kept: 1,
               counted: 2,
               rate: 50,
               skipped: 0,
               missed: 1,
               avg_deviation: -3
             },
             %{
               name: "Gassi",
               kept: 2,
               counted: 2,
               rate: 100,
               skipped: 1,
               missed: 0,
               avg_deviation: 12
             },
             %{name: "Spielen", counted: 0, rate: nil, skipped: 1, avg_deviation: nil}
           ] = compute("1w", lukas).routines

    assert breakfast_id == breakfast.id
  end

  test "range clipped to arrival", %{lukas: lukas, profile: profile} do
    {:ok, _} =
      PuppyLog.Puppy.update_profile(profile, %{arrival_date: ~D[2026-11-08]}, actor: lukas)

    breakfast = routine(lukas, "Frühstück")
    occ(breakfast, ~D[2026-11-07], :done, 0)
    occ(breakfast, ~D[2026-11-08], :done, 0)
    potty(lukas, ~D[2026-11-07], %{pee: true, location: :inside})

    stats = compute("2w", lukas)

    assert stats.range == Date.range(~D[2026-11-08], @today)
    assert stats.previous_range == nil
    assert %{kept: 1, counted: 1, accidents: 0, previous_accidents: nil} = stats
    assert length(stats.buckets) == 5
  end

  test "without arrival date there is nothing to count", %{lukas: lukas, profile: profile} do
    {:ok, _} = PuppyLog.Puppy.update_profile(profile, %{arrival_date: nil}, actor: lukas)

    assert %{counted: 0, kept: 0, rate: nil, buckets: [], routines: [], accidents: 0} =
             compute("1w", lukas)
  end
end
