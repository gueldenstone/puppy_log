defmodule PuppyLog.Puppy.ProfileTest do
  use PuppyLog.DataCase, async: false

  alias PuppyLog.Puppy

  setup do
    %{lukas: user_fixture(%{name: "Lukas"}), riv: user_fixture(%{name: "Riv"})}
  end

  test "there is no profile until it is created", %{lukas: lukas} do
    assert {:ok, nil} = Puppy.get_profile(actor: lukas)
  end

  test "creating and updating records who did it", %{lukas: lukas, riv: riv} do
    {:ok, profile} =
      Puppy.create_profile(
        %{
          name: " Bruno ",
          birth_date: ~D[2026-08-01],
          breed: "Labrador",
          chip_number: "276098106543210"
        },
        actor: lukas
      )

    assert profile.name == "Bruno"
    assert profile.created_by_id == lukas.id
    assert profile.updated_by_id == lukas.id

    {:ok, updated} = Puppy.update_profile(profile, %{breed: "Labrador Retriever"}, actor: riv)
    assert updated.breed == "Labrador Retriever"
    assert updated.created_by_id == lukas.id
    assert updated.updated_by_id == riv.id

    assert {:ok, %{id: id}} = Puppy.get_profile(actor: riv)
    assert id == profile.id
  end

  test "chip numbers may be typed with spaces", %{lukas: lukas} do
    {:ok, profile} =
      Puppy.create_profile(%{name: "Bruno", chip_number: "276 098 106-543 210"}, actor: lukas)

    assert profile.chip_number == "276098106543210"
  end

  test "stores the arrival date", %{lukas: lukas} do
    {:ok, profile} =
      Puppy.create_profile(%{name: "Bruno", arrival_date: ~D[2026-12-01]}, actor: lukas)

    assert profile.arrival_date == ~D[2026-12-01]
  end

  test "only one puppy can exist", %{lukas: lukas} do
    {:ok, _} = Puppy.create_profile(%{name: "Bruno"}, actor: lukas)
    assert {:error, _} = Puppy.create_profile(%{name: "Zweiter"}, actor: lukas)
  end

  test "validates name, chip number and birth date", %{lukas: lukas} do
    assert {:error, %Ash.Error.Invalid{} = error} =
             Puppy.create_profile(
               %{name: "", chip_number: "1234", birth_date: Date.add(PuppyLog.Clock.today(), 1)},
               actor: lukas
             )

    fields = Enum.map(error.errors, & &1.field)
    assert :name in fields
    assert :chip_number in fields
    assert :birth_date in fields
  end

  test "requires a signed in user", %{lukas: lukas} do
    assert {:error, _} = Puppy.create_profile(%{name: "Bruno"})

    {:ok, _} = Puppy.create_profile(%{name: "Bruno"}, actor: lukas)
    # reads without actor are filtered by the policy, nothing leaks
    assert {:ok, nil} = Puppy.get_profile()
  end

  test "changes are broadcast", %{lukas: lukas} do
    PuppyLogWeb.Endpoint.subscribe("puppy_profile:changed")
    {:ok, _} = Puppy.create_profile(%{name: "Bruno"}, actor: lukas)
    assert_receive %Phoenix.Socket.Broadcast{topic: "puppy_profile:changed"}
  end
end
