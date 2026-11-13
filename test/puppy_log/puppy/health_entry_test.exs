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

  describe "due at an age" do
    setup %{lukas: lukas} do
      pin_clock(DateTime.new!(~D[2026-11-13], ~T[10:00:00], "Europe/Berlin"))
      {:ok, _} = Puppy.create_profile(%{name: "Momo", birth_date: ~D[2026-10-07]}, actor: lukas)
      :ok
    end

    defp age_attrs(attrs \\ %{}) do
      Map.merge(
        %{kind: :vaccination, title: "Impfung", due_age: 8, due_age_unit: :weeks},
        attrs
      )
    end

    defp error_for(result, field) do
      assert {:error, %Ash.Error.Invalid{errors: errors}} = result
      Enum.find(errors, &(&1.field == field))
    end

    test "an age sets the due date from the birth date", %{lukas: lukas} do
      {:ok, entry} = Puppy.create_health_entry(age_attrs(), actor: lukas)
      assert entry.due_on == ~D[2026-12-02]
      assert entry.due_age == 8
    end

    test "changing the age recomputes the date", %{lukas: lukas} do
      {:ok, entry} = Puppy.create_health_entry(age_attrs(), actor: lukas)
      {:ok, entry} = Puppy.update_health_entry(entry, %{due_age: 9}, actor: lukas)
      assert entry.due_on == ~D[2026-12-09]
    end

    test "switching to a fixed date drops the age", %{lukas: lukas} do
      {:ok, entry} = Puppy.create_health_entry(age_attrs(), actor: lukas)

      {:ok, entry} =
        Puppy.update_health_entry(
          entry,
          %{due_age: nil, due_age_unit: nil, due_on: ~D[2026-12-05]},
          actor: lukas
        )

      assert entry.due_on == ~D[2026-12-05]
      assert entry.due_age == nil
    end

    test "age needs both number and unit", %{lukas: lukas} do
      result =
        Puppy.create_health_entry(age_attrs(%{due_age_unit: nil, due_on: ~D[2026-12-01]}),
          actor: lukas
        )

      assert error_for(result, :due_age_unit).message =~ "Wochen oder Monate"

      result =
        Puppy.create_health_entry(age_attrs(%{due_age: nil, due_on: ~D[2026-12-01]}),
          actor: lukas
        )

      assert error_for(result, :due_age).message =~ "Alter"
    end

    test "age is only for care items", %{lukas: lukas} do
      vet = age_attrs(%{kind: :vet_visit, due_time: ~T[09:30:00], due_on: ~D[2026-12-01]})
      assert error_for(Puppy.create_health_entry(vet, actor: lukas), :due_age)
    end

    test "age needs a birth date", %{lukas: lukas} do
      {:ok, _} =
        Puppy.update_profile(Puppy.get_profile!(authorize?: false), %{birth_date: nil},
          actor: lukas
        )

      result = Puppy.create_health_entry(age_attrs(), actor: lukas)
      assert error_for(result, :due_age).message == "Erst das Geburtsdatum im Profil eintragen"
    end

    test "age out of range", %{lukas: lukas} do
      assert error_for(
               Puppy.create_health_entry(age_attrs(%{due_age: 105}), actor: lukas),
               :due_age
             )

      assert error_for(
               Puppy.create_health_entry(age_attrs(%{due_age: 37, due_age_unit: :months}),
                 actor: lukas
               ),
               :due_age
             )
    end

    test "a corrected birth date moves open age entries only", %{lukas: lukas} do
      {:ok, open} = Puppy.create_health_entry(age_attrs(), actor: lukas)

      {:ok, done} =
        Puppy.create_health_entry(age_attrs(%{status: :done, done_on: ~D[2026-11-12]}),
          actor: lukas
        )

      {:ok, fixed} = Puppy.create_health_entry(care_attrs(), actor: lukas)

      PuppyLogWeb.Endpoint.subscribe("health_entries:changed")
      profile = Puppy.get_profile!(authorize?: false)
      {:ok, _} = Puppy.update_profile(profile, %{birth_date: ~D[2026-10-01]}, actor: lukas)

      assert Puppy.get_health_entry!(open.id, actor: lukas).due_on == ~D[2026-11-26]
      assert Puppy.get_health_entry!(done.id, actor: lukas).due_on == done.due_on
      assert Puppy.get_health_entry!(fixed.id, actor: lukas).due_on == ~D[2026-12-01]
      assert_receive %Phoenix.Socket.Broadcast{topic: "health_entries:changed"}
    end

    test "editing an open age entry without a birth date keeps its date", %{lukas: lukas} do
      {:ok, open} = Puppy.create_health_entry(age_attrs(), actor: lukas)
      profile = Puppy.get_profile!(authorize?: false)
      {:ok, _} = Puppy.update_profile(profile, %{birth_date: nil}, actor: lukas)

      assert {:ok, entry} = Puppy.update_health_entry(open, %{title: "Neu"}, actor: lukas)
      assert entry.title == "Neu"
      assert entry.due_on == ~D[2026-12-02]
    end

    test "editing a done age entry after a birth date correction keeps its date", %{lukas: lukas} do
      {:ok, done} =
        Puppy.create_health_entry(age_attrs(%{status: :done, done_on: ~D[2026-11-12]}),
          actor: lukas
        )

      profile = Puppy.get_profile!(authorize?: false)
      {:ok, _} = Puppy.update_profile(profile, %{birth_date: ~D[2026-10-01]}, actor: lukas)

      assert {:ok, entry} = Puppy.update_health_entry(done, %{title: "Neu"}, actor: lukas)
      assert entry.due_on == ~D[2026-12-02]
    end

    test "changing the age of a done entry recomputes its date", %{lukas: lukas} do
      {:ok, done} =
        Puppy.create_health_entry(age_attrs(%{status: :done, done_on: ~D[2026-11-12]}),
          actor: lukas
        )

      {:ok, entry} = Puppy.update_health_entry(done, %{due_age: 9}, actor: lukas)
      assert entry.due_on == ~D[2026-12-09]
    end

    test "removing the birth date keeps the dates", %{lukas: lukas} do
      {:ok, open} = Puppy.create_health_entry(age_attrs(), actor: lukas)
      profile = Puppy.get_profile!(authorize?: false)

      assert {:ok, _} = Puppy.update_profile(profile, %{birth_date: nil}, actor: lukas)
      assert Puppy.get_health_entry!(open.id, actor: lukas).due_on == ~D[2026-12-02]
    end
  end
end
