defmodule PuppyLog.Puppy.HealthEntryTest do
  use PuppyLog.DataCase, async: false

  alias PuppyLog.{Daily, Puppy}

  setup do
    %{lukas: user_fixture(%{name: "Lukas"}), riv: user_fixture(%{name: "Riv"})}
  end

  defp care_attrs(attrs \\ %{}) do
    Map.merge(%{kind: :vaccination, title: "Impfung", due_on: ~D[2026-12-01]}, attrs)
  end

  test "creates a care item with the household default lead time", %{lukas: lukas} do
    {:ok, _} = Daily.save_settings(%{health_reminder_days: 3}, actor: lukas)

    {:ok, entry} = Puppy.create_health_entry(care_attrs(), actor: lukas)

    assert entry.remind_days_before == 3
    assert entry.status == :open
    assert entry.created_by_id == lukas.id

    {:ok, entry} = Puppy.create_health_entry(care_attrs(%{remind_days_before: 5}), actor: lukas)
    assert entry.remind_days_before == 5
  end

  test "default lead time is 2 without saved settings", %{lukas: lukas} do
    {:ok, entry} = Puppy.create_health_entry(care_attrs(), actor: lukas)
    assert entry.remind_days_before == 2
  end

  test "vet visit needs a time, care items reject time/location/assignee", %{
    lukas: lukas,
    riv: riv
  } do
    vet = %{kind: :vet_visit, title: "Kontrolle", due_on: ~D[2026-12-01]}

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             Puppy.create_health_entry(vet, actor: lukas)

    assert Enum.any?(errors, &(&1.field == :due_time))

    assert {:ok, entry} =
             Puppy.create_health_entry(
               Map.merge(vet, %{due_time: ~T[09:30:00], location: "Praxis", assignee_id: riv.id}),
               actor: lukas
             )

    assert entry.assignee_id == riv.id

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             Puppy.create_health_entry(
               care_attrs(%{due_time: ~T[09:30:00], location: "Praxis", assignee_id: riv.id}),
               actor: lukas
             )

    fields = Enum.map(errors, & &1.field)
    assert :due_time in fields
    assert :location in fields
    assert :assignee_id in fields
  end

  test "batch only for vaccinations", %{lukas: lukas} do
    assert {:ok, _} = Puppy.create_health_entry(care_attrs(%{batch: "A123"}), actor: lukas)

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             Puppy.create_health_entry(
               care_attrs(%{kind: :deworming, batch: "A123"}),
               actor: lukas
             )

    assert Enum.any?(errors, &(&1.field == :batch))
  end

  test "repeat only for care kinds", %{lukas: lukas} do
    assert {:ok, %{repeat_weeks: 12}} =
             Puppy.create_health_entry(care_attrs(%{repeat_weeks: 12}), actor: lukas)

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             Puppy.create_health_entry(
               %{
                 kind: :vet_visit,
                 title: "Kontrolle",
                 due_on: ~D[2026-12-01],
                 due_time: ~T[09:30:00],
                 repeat_weeks: 12
               },
               actor: lukas
             )

    assert Enum.any?(errors, &(&1.field == :repeat_weeks))

    assert {:error, _} = Puppy.create_health_entry(care_attrs(%{repeat_weeks: 0}), actor: lukas)
    assert {:error, _} = Puppy.create_health_entry(care_attrs(%{repeat_weeks: 105}), actor: lukas)
  end

  test "overview lists open by due date, then done newest first", %{lukas: lukas} do
    {:ok, _} =
      Puppy.create_health_entry(care_attrs(%{title: "B", due_on: ~D[2026-12-10]}), actor: lukas)

    {:ok, _} =
      Puppy.create_health_entry(care_attrs(%{title: "A", due_on: ~D[2026-12-01]}), actor: lukas)

    {:ok, _} =
      Puppy.create_health_entry(
        %{kind: :vet_visit, title: "V", due_on: ~D[2026-12-01], due_time: ~T[08:00:00]},
        actor: lukas
      )

    for {title, done_on} <- [{"D1", ~D[2026-10-01]}, {"D2", ~D[2026-10-20]}] do
      {:ok, _} =
        Puppy.create_health_entry(
          care_attrs(%{title: title, status: :done, done_on: done_on}),
          actor: lukas
        )
    end

    assert Puppy.list_health_entries!(actor: lukas) |> Enum.map(& &1.title) ==
             ["A", "V", "B", "D2", "D1"]
  end

  test "requires a signed in user" do
    assert {:error, _} = Puppy.create_health_entry(care_attrs())
  end

  test "both members can update and delete", %{lukas: lukas, riv: riv} do
    {:ok, entry} = Puppy.create_health_entry(care_attrs(), actor: lukas)
    {:ok, entry} = Puppy.update_health_entry(entry, %{title: "Tollwut"}, actor: riv)
    assert entry.title == "Tollwut"
    assert {:ok, %{title: "Tollwut"}} = Puppy.get_health_entry(entry.id, actor: riv)
    assert :ok = Puppy.delete_health_entry(entry, actor: riv)
  end

  test "broadcasts health_entries:changed", %{lukas: lukas} do
    PuppyLogWeb.Endpoint.subscribe("health_entries:changed")
    {:ok, _} = Puppy.create_health_entry(care_attrs(), actor: lukas)
    assert_receive %Phoenix.Socket.Broadcast{topic: "health_entries:changed"}
  end
end
