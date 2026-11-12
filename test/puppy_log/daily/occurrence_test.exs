defmodule PuppyLog.Daily.OccurrenceTest do
  use PuppyLog.DataCase, async: false

  alias PuppyLog.{Clock, Daily}

  @today ~D[2026-11-12]

  setup do
    lukas = user_fixture(%{name: "Lukas"})
    riv = user_fixture(%{name: "Riv"})
    pin_local(~D[2026-11-01], ~T[06:00:00])

    {:ok, _} =
      PuppyLog.Puppy.create_profile(%{name: "Fiete", arrival_date: ~D[2026-11-01]},
        actor: lukas
      )

    %{lukas: lukas, riv: riv}
  end

  defp pin_local(date, time), do: pin_clock(Clock.local_datetime(date, time))

  defp occurrence(actor, date, starts_at) do
    {:ok, routine} =
      Daily.create_routine(%{name: "Lösen", kind: :potty, starts_at: starts_at}, actor: actor)

    :ok = Daily.ensure_day(date, [])
    [occurrence] = Daily.list_occurrences_on!(date, actor: actor)
    assert occurrence.routine_id == routine.id
    occurrence
  end

  test "complete stores time, deviation and who", %{lukas: lukas} do
    occ = occurrence(lukas, @today, ~T[10:00:00])

    {:ok, done} =
      Daily.complete_occurrence(
        occ,
        %{done_at: Clock.local_datetime(@today, ~T[10:20:00])},
        actor: lukas
      )

    assert done.status == :done
    assert done.done_at == ~U[2026-11-12 09:20:00.000000Z]
    assert done.deviation_minutes == 20
    assert done.completed_by_id == lukas.id

    assert Daily.get_occurrence!(occ.id, actor: lukas).status == :done
  end

  test "second completion fails", %{lukas: lukas, riv: riv} do
    occ = occurrence(lukas, @today, ~T[10:00:00])
    done_at = Clock.local_datetime(@today, ~T[10:05:00])

    {:ok, done} = Daily.complete_occurrence(occ, %{done_at: done_at}, actor: lukas)

    # with the record as it is now
    assert {:error, %Ash.Error.Invalid{} = error} =
             Daily.complete_occurrence(done, %{done_at: done_at}, actor: riv)

    assert Exception.message(error) =~ "Schon erledigt"

    # with a stale copy that still looks open (a concurrent tick in another session)
    assert {:error, %Ash.Error.Invalid{} = error} =
             Daily.complete_occurrence(occ, %{done_at: done_at}, actor: riv)

    assert Exception.message(error) =~ "Schon erledigt"

    assert {:error, %Ash.Error.Invalid{} = error} = Daily.skip_occurrence(occ, actor: riv)
    assert Exception.message(error) =~ "Schon erledigt"

    reloaded = Daily.get_occurrence!(occ.id, actor: lukas)
    assert reloaded.status == :done
    assert reloaded.completed_by_id == lukas.id
  end

  test "concurrent completions: only one wins", %{lukas: lukas, riv: riv} do
    occ = occurrence(lukas, @today, ~T[10:00:00])
    done_at = Clock.local_datetime(@today, ~T[10:05:00])

    results =
      [lukas, riv, lukas, riv]
      |> Enum.map(fn user ->
        Task.async(fn -> Daily.complete_occurrence(occ, %{done_at: done_at}, actor: user) end)
      end)
      |> Task.await_many()

    assert [{:ok, _}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert Enum.count(results, &match?({:error, %Ash.Error.Invalid{}}, &1)) == 3
  end

  test "skip and reopen", %{lukas: lukas, riv: riv} do
    occ = occurrence(lukas, @today, ~T[10:00:00])

    {:ok, skipped} = Daily.skip_occurrence(occ, actor: riv)
    assert skipped.status == :skipped
    assert skipped.completed_by_id == riv.id

    {:ok, reopened} = Daily.reopen_occurrence(skipped, actor: lukas)
    assert reopened.status == :open
    assert reopened.completed_by_id == nil

    {:ok, done} =
      Daily.complete_occurrence(
        reopened,
        %{done_at: Clock.local_datetime(@today, ~T[10:00:00]), event_id: Ash.UUID.generate()},
        actor: lukas
      )

    assert done.event_id

    {:ok, reopened} = Daily.reopen_occurrence(done, actor: lukas)
    assert reopened.status == :open
    assert reopened.done_at == nil
    assert reopened.deviation_minutes == nil
    assert reopened.completed_by_id == nil
    assert reopened.event_id == nil
  end

  test "late tick for yesterday's 02:00 routine at 07:00 today", %{lukas: lukas} do
    yesterday = Date.add(@today, -1)
    pin_local(yesterday, ~T[01:00:00])
    occ = occurrence(lukas, yesterday, ~T[02:00:00])

    pin_local(@today, ~T[07:00:00])

    {:ok, done} =
      Daily.complete_occurrence(occ, %{done_at: Clock.now()}, actor: lukas)

    assert done.deviation_minutes == 1740
  end

  test "requires a signed in user", %{lukas: lukas} do
    occ = occurrence(lukas, @today, ~T[10:00:00])
    assert {:error, %Ash.Error.Forbidden{}} = Daily.skip_occurrence(occ)
  end
end
