defmodule PuppyLog.Daily.PlannerTest do
  use PuppyLog.DataCase, async: false

  alias PuppyLog.{Clock, Daily}

  @today ~D[2026-11-12]

  setup do
    lukas = user_fixture(%{name: "Lukas"})
    pin_local(~D[2026-11-01], ~T[06:00:00])

    {:ok, profile} =
      PuppyLog.Puppy.create_profile(%{name: "Fiete", arrival_date: ~D[2026-11-01]},
        actor: lukas
      )

    pin_local(@today, ~T[09:00:00])
    %{lukas: lukas, profile: profile}
  end

  defp pin_local(date, time), do: pin_clock(Clock.local_datetime(date, time))

  defp routine(actor, extra \\ %{}) do
    {:ok, routine} =
      Daily.create_routine(
        Map.merge(%{name: "Frühstück", kind: :meal, starts_at: ~T[07:00:00]}, extra),
        actor: actor
      )

    routine
  end

  defp on(date, actor), do: Daily.list_occurrences_on!(date, actor: actor)

  test "plans routines on their weekdays", %{lukas: lukas} do
    pin_local(~D[2026-11-10], ~T[06:00:00])
    routine(lukas, %{weekdays: [1, 2, 3, 4, 5]})
    pin_local(@today, ~T[09:00:00])

    assert :ok = Daily.ensure_day(~D[2026-11-12], [])
    assert :ok = Daily.ensure_day(~D[2026-11-14], [])

    assert [occurrence] = on(~D[2026-11-12], lukas)
    assert occurrence.name == "Frühstück"
    assert occurrence.kind == :meal
    assert occurrence.planned_start == ~T[07:00:00]
    assert occurrence.status == :open
    assert on(~D[2026-11-14], lukas) == []
  end

  test "nothing before arrival or without arrival date", %{lukas: lukas, profile: profile} do
    pin_local(~D[2026-10-20], ~T[06:00:00])
    routine(lukas)
    pin_local(@today, ~T[09:00:00])

    Daily.ensure_day(~D[2026-10-31], [])
    assert on(~D[2026-10-31], lukas) == []

    {:ok, _} = PuppyLog.Puppy.update_profile(profile, %{arrival_date: nil}, actor: lukas)
    Daily.ensure_day(@today, [])
    assert on(@today, lukas) == []
  end

  test "ensure_days covers the range clipped to arrival and today", %{lukas: lukas} do
    pin_local(~D[2026-10-20], ~T[06:00:00])
    routine(lukas)
    pin_local(@today, ~T[09:00:00])

    assert :ok = Daily.ensure_days(~D[2026-10-25], ~D[2026-11-20], [])

    dates =
      Daily.Occurrence
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.date)
      |> Enum.sort(Date)

    assert dates == Enum.to_list(Date.range(~D[2026-11-01], @today))
  end

  test "routines count only from the day they were created", %{lukas: lukas} do
    routine(lukas)

    Daily.ensure_days(~D[2026-11-01], @today, [])
    assert on(~D[2026-11-11], lukas) == []
  end

  test "planning broadcasts occurrences:changed", %{lukas: lukas} do
    routine = routine(lukas, %{starts_at: ~T[10:00:00], weekdays: [1, 2, 3, 5]})
    PuppyLogWeb.Endpoint.subscribe("occurrences:changed")

    Daily.ensure_day(~D[2026-11-13], [])
    assert_receive %{topic: "occurrences:changed", payload: %{data: %{date: ~D[2026-11-13]}}}

    # a routine edit that adds today's weekday plans today's occurrence
    {:ok, _} = Daily.update_routine(routine, %{weekdays: [4]}, actor: lukas)
    assert_receive %{topic: "occurrences:changed", payload: %{data: %{date: @today}}}
  end

  test "idempotent", %{lukas: lukas} do
    routine(lukas, %{starts_at: ~T[10:00:00]})

    Daily.ensure_day(@today, [])
    Daily.ensure_day(@today, [])
    assert [occurrence] = on(@today, lukas)

    {:ok, _} =
      Daily.complete_occurrence(occurrence, %{done_at: Clock.now()}, actor: lukas)

    Daily.ensure_day(@today, [])
    assert [%{status: :done, completed_by_id: id}] = on(@today, lukas)
    assert id == lukas.id
  end

  test "a racing plan upsert leaves an existing occurrence untouched", %{lukas: lukas} do
    routine = routine(lukas, %{starts_at: ~T[10:00:00]})
    Daily.ensure_day(@today, [])
    [occurrence] = on(@today, lukas)
    {:ok, _} = Daily.skip_occurrence(occurrence, actor: lukas)

    Daily.Occurrence
    |> Ash.Changeset.for_create(:plan, %{
      routine_id: routine.id,
      date: @today,
      name: "Anders",
      kind: :meal,
      planned_start: ~T[11:00:00]
    })
    |> Ash.create!(authorize?: false)

    assert [%{status: :skipped, name: "Frühstück", planned_start: ~T[10:00:00]}] =
             on(@today, lukas)
  end

  test "routine created during the day counts only if still ahead", %{lukas: lukas} do
    pin_local(@today, ~T[15:00:00])
    routine(lukas, %{name: "Morgens", starts_at: ~T[07:00:00]})
    routine(lukas, %{name: "Abends", starts_at: ~T[18:00:00]})

    Daily.ensure_day(@today, [])
    assert [%{name: "Abends"}] = on(@today, lukas)

    Daily.ensure_day(Date.add(@today, 1), [])
    assert ["Morgens", "Abends"] = Enum.map(on(Date.add(@today, 1), lukas), & &1.name)
  end

  test "editing a routine changes today's open occurrence, not past ones", %{lukas: lukas} do
    pin_local(~D[2026-11-11], ~T[06:00:00])
    routine = routine(lukas)
    Daily.ensure_day(~D[2026-11-11], [])

    pin_local(@today, ~T[06:00:00])
    Daily.ensure_day(@today, [])

    {:ok, _} =
      Daily.update_routine(routine, %{starts_at: ~T[07:30:00], name: "Futter"}, actor: lukas)

    assert [%{planned_start: ~T[07:00:00], name: "Frühstück"}] = on(~D[2026-11-11], lukas)
    assert [%{planned_start: ~T[07:30:00], name: "Futter"}] = on(@today, lukas)
  end

  test "editing a routine leaves a done occurrence of today alone", %{lukas: lukas} do
    pin_local(@today, ~T[06:00:00])
    routine = routine(lukas)
    Daily.ensure_day(@today, [])
    [occurrence] = on(@today, lukas)
    {:ok, _} = Daily.skip_occurrence(occurrence, actor: lukas)

    {:ok, _} = Daily.update_routine(routine, %{starts_at: ~T[07:30:00]}, actor: lukas)

    assert [%{planned_start: ~T[07:00:00], status: :skipped}] = on(@today, lukas)
  end

  test "archiving removes today's open occurrence, keeps history", %{lukas: lukas} do
    pin_local(~D[2026-11-11], ~T[06:00:00])
    routine = routine(lukas)
    Daily.ensure_day(~D[2026-11-11], [])

    pin_local(@today, ~T[06:00:00])
    Daily.ensure_day(@today, [])
    assert [_] = on(@today, lukas)

    {:ok, _} = Daily.archive_routine(routine, actor: lukas)

    assert on(@today, lukas) == []
    assert [%{name: "Frühstück"}] = on(~D[2026-11-11], lukas)

    Daily.ensure_day(@today, [])
    assert on(@today, lukas) == []
  end

  test "an archived routine is still planned for days before its archiving", %{lukas: lukas} do
    pin_local(~D[2026-11-05], ~T[06:00:00])
    routine = routine(lukas)

    pin_local(@today, ~T[09:00:00])
    {:ok, _} = Daily.archive_routine(routine, actor: lukas)

    Daily.ensure_days(~D[2026-11-10], @today, [])
    assert [_] = on(~D[2026-11-11], lukas)
    assert on(@today, lukas) == []
  end

  test "DST spring-forward day plans 02:30 without crashing", %{lukas: lukas} do
    pin_local(~D[2026-03-01], ~T[06:00:00])

    {:ok, _} =
      PuppyLog.Puppy.update_profile(
        PuppyLog.Puppy.get_profile!(actor: lukas),
        %{arrival_date: ~D[2026-03-01]},
        actor: lukas
      )

    routine(lukas, %{name: "Nachtrunde", kind: :potty, starts_at: ~T[02:30:00]})
    pin_local(~D[2026-03-29], ~T[12:00:00])

    assert :ok = Daily.ensure_day(~D[2026-03-29], [])
    assert [%{planned_start: ~T[02:30:00]}] = on(~D[2026-03-29], lukas)
  end
end
