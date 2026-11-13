defmodule PuppyLog.Puppy.HealthCompletionTest do
  use PuppyLog.DataCase, async: false

  alias PuppyLog.Puppy
  alias PuppyLog.Puppy.{HealthEntry, HealthStatus}

  require Ash.Query

  setup do
    pin_clock(DateTime.new!(~D[2026-11-13], ~T[10:00:00], "Europe/Berlin"))
    %{lukas: user_fixture(%{name: "Lukas"}), riv: user_fixture(%{name: "Riv"})}
  end

  defp create(actor, attrs \\ %{}) do
    Map.merge(%{kind: :vaccination, title: "Impfung", due_on: ~D[2026-11-10]}, attrs)
    |> Puppy.create_health_entry!(actor: actor)
  end

  defp successors(entry, actor),
    do:
      HealthEntry
      |> Ash.Query.filter(previous_id == ^entry.id)
      |> Ash.read!(actor: actor)

  test "complete stores date and batch and keeps the creator", %{lukas: lukas} do
    entry = create(lukas)

    {:ok, done} =
      Puppy.complete_health_entry(entry, %{done_on: ~D[2026-11-12], batch: "A123"}, actor: lukas)

    assert %{status: :done, done_on: ~D[2026-11-12], batch: "A123"} = done
    assert done.created_by_id == lukas.id
  end

  test "complete without batch keeps the stored batch", %{lukas: lukas} do
    entry = create(lukas, %{batch: "A1"})
    {:ok, done} = Puppy.complete_health_entry(entry, %{}, actor: lukas)
    assert done.batch == "A1"
  end

  test "complete rejects a batch on a non-vaccination", %{lukas: lukas} do
    entry = create(lukas, %{kind: :deworming})

    assert {:error, error} = Puppy.complete_health_entry(entry, %{batch: "X"}, actor: lukas)
    assert Enum.any?(error.errors, &(&1.field == :batch and &1.message =~ "Nur für Impfungen"))
  end

  test "reopen of an open entry fails", %{lukas: lukas} do
    assert {:error, error} = Puppy.reopen_health_entry(create(lukas), actor: lukas)
    assert Exception.message(error) =~ "Ist noch offen"
  end

  test "create rejects done_on without status done", %{lukas: lukas} do
    assert {:error, error} =
             Puppy.create_health_entry(
               %{kind: :other_care, title: "X", due_on: ~D[2026-11-10], done_on: ~D[2026-11-01]},
               actor: lukas
             )

    assert Enum.any?(error.errors, &(&1.field == :done_on))
  end

  test "complete defaults the date to today", %{lukas: lukas} do
    {:ok, done} = Puppy.complete_health_entry(create(lukas), %{}, actor: lukas)
    assert done.done_on == ~D[2026-11-13]
  end

  test "second completion fails with Schon erledigt", %{lukas: lukas, riv: riv} do
    entry = create(lukas, %{repeat_weeks: 4})
    {:ok, _} = Puppy.complete_health_entry(entry, %{}, actor: lukas)

    assert {:error, error} = Puppy.complete_health_entry(entry, %{}, actor: riv)
    assert Exception.message(error) =~ "Schon erledigt"
    assert [_one] = successors(entry, lukas)
  end

  test "repeating care item creates the next one from the completion date", %{
    lukas: lukas,
    riv: riv
  } do
    entry = create(lukas, %{repeat_weeks: 4, notes: "Notiz", remind_days_before: 5})
    {:ok, _} = Puppy.complete_health_entry(entry, %{done_on: ~D[2026-11-13]}, actor: riv)

    assert [next] = successors(entry, lukas)
    assert next.due_on == ~D[2026-12-11]
    assert next.previous_id == entry.id
    assert %{status: :open, kind: :vaccination, title: "Impfung", notes: "Notiz"} = next
    assert %{remind_days_before: 5, repeat_weeks: 4, assignee_id: nil, batch: nil} = next
    assert next.created_by_id == riv.id
  end

  test "successor broadcasts a change", %{lukas: lukas} do
    entry = create(lukas, %{repeat_weeks: 1})
    PuppyLogWeb.Endpoint.subscribe("health_entries:changed")
    {:ok, _} = Puppy.complete_health_entry(entry, %{}, actor: lukas)

    assert_receive %{payload: %{data: %{status: :done}}}
    assert_receive %{payload: %{data: %{status: :open, previous_id: previous}}}
    assert previous == entry.id
  end

  test "entered as done in the past still creates the successor", %{lukas: lukas} do
    entry =
      create(lukas, %{status: :done, done_on: ~D[2026-09-30], repeat_weeks: 4})

    assert entry.status == :done
    assert [next] = successors(entry, lukas)
    assert next.due_on == ~D[2026-10-28]
    assert HealthStatus.state(next, PuppyLog.Clock.now()) == :overdue
  end

  test "no successor without repetition", %{lukas: lukas} do
    entry = create(lukas)
    {:ok, _} = Puppy.complete_health_entry(entry, %{}, actor: lukas)
    assert successors(entry, lukas) == []
  end

  test "completing a vet visit only marks it done", %{lukas: lukas} do
    visit = create(lukas, %{kind: :vet_visit, due_time: ~T[09:00:00]})
    {:ok, done} = Puppy.complete_health_entry(visit, %{}, actor: lukas)
    assert done.status == :done
    assert successors(visit, lukas) == []
  end

  test "reopen removes an untouched open successor", %{lukas: lukas} do
    entry = create(lukas, %{repeat_weeks: 4})
    {:ok, done} = Puppy.complete_health_entry(entry, %{batch: "X"}, actor: lukas)

    {:ok, reopened} = Puppy.reopen_health_entry(done, actor: lukas)

    assert %{status: :open, done_on: nil, batch: nil} = reopened
    assert successors(entry, lukas) == []
  end

  test "reopen keeps a successor that was already edited or completed", %{lukas: lukas} do
    edited = create(lukas, %{title: "A", repeat_weeks: 4})
    {:ok, done} = Puppy.complete_health_entry(edited, %{}, actor: lukas)
    [next] = successors(edited, lukas)
    {:ok, _} = Puppy.update_health_entry(next, %{title: "A2"}, actor: lukas)
    {:ok, _} = Puppy.reopen_health_entry(done, actor: lukas)
    assert [_kept] = successors(edited, lukas)

    completed = create(lukas, %{title: "B", repeat_weeks: 4})
    {:ok, done} = Puppy.complete_health_entry(completed, %{}, actor: lukas)
    [next] = successors(completed, lukas)
    {:ok, _} = Puppy.complete_health_entry(next, %{}, actor: lukas)
    {:ok, _} = Puppy.reopen_health_entry(done, actor: lukas)
    assert [%{status: :done}] = successors(completed, lukas)
  end

  test "future done_on is rejected", %{lukas: lukas} do
    entry = create(lukas)

    assert {:error, error} =
             Puppy.complete_health_entry(entry, %{done_on: ~D[2026-11-14]}, actor: lukas)

    assert Enum.any?(
             error.errors,
             &(&1.field == :done_on and &1.message =~ "Darf nicht in der Zukunft liegen")
           )

    assert {:error, _} =
             Puppy.create_health_entry(
               %{
                 kind: :other_care,
                 title: "X",
                 due_on: ~D[2026-11-10],
                 status: :done,
                 done_on: ~D[2026-11-14]
               },
               actor: lukas
             )
  end

  test "the successor of an age entry has a fixed date", %{lukas: lukas} do
    pin_clock(DateTime.new!(~D[2026-12-04], ~T[10:00:00], "Europe/Berlin"))
    {:ok, _} = Puppy.create_profile(%{name: "Momo", birth_date: ~D[2026-10-07]}, actor: lukas)
    entry = create(lukas, %{due_on: nil, due_age: 8, due_age_unit: :weeks, repeat_weeks: 4})

    {:ok, _} = Puppy.complete_health_entry(entry, %{done_on: ~D[2026-12-03]}, actor: lukas)
    [successor] = successors(entry, lukas)
    assert successor.due_on == ~D[2026-12-31]
    assert successor.due_age == nil
    assert successor.due_age_unit == nil
  end
end
