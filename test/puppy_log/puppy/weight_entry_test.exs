defmodule PuppyLog.Puppy.WeightEntryTest do
  use PuppyLog.DataCase, async: false

  alias PuppyLog.Puppy

  setup do
    %{lukas: user_fixture(%{name: "Lukas"}), riv: user_fixture(%{name: "Riv"})}
  end

  test "adds a weighing for today by default and records who made it", %{lukas: lukas} do
    {:ok, entry} = Puppy.add_weight(%{weight_grams: 4350}, actor: lukas)

    assert entry.measured_on == PuppyLog.Clock.today()
    assert entry.created_by_id == lukas.id
  end

  test "accepts German kg input", %{lukas: lukas} do
    {:ok, entry} = Puppy.add_weight(%{weight_kg: "4,35"}, actor: lukas)
    assert entry.weight_grams == 4350

    {:ok, entry} = Puppy.update_weight(entry, %{weight_kg: "4.5 kg"}, actor: lukas)
    assert entry.weight_grams == 4500

    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             Puppy.add_weight(%{weight_kg: "viel"}, actor: lukas)

    assert Enum.any?(errors, &(&1.field == :weight_kg))
  end

  test "history is newest first", %{lukas: lukas, riv: riv} do
    {:ok, _} = Puppy.add_weight(%{weight_grams: 4000, measured_on: ~D[2026-10-01]}, actor: lukas)
    {:ok, _} = Puppy.add_weight(%{weight_grams: 5000, measured_on: ~D[2026-11-01]}, actor: riv)
    {:ok, _} = Puppy.add_weight(%{weight_grams: 4500, measured_on: ~D[2026-10-15]}, actor: lukas)

    assert Puppy.list_weights!(actor: lukas) |> Enum.map(& &1.weight_grams) == [5000, 4500, 4000]
  end

  test "weight_summary returns latest and change", %{lukas: lukas} do
    assert %{latest: nil} = Puppy.weight_summary(actor: lukas)

    {:ok, _} = Puppy.add_weight(%{weight_grams: 4000, measured_on: ~D[2026-10-01]}, actor: lukas)

    assert %{latest: %{weight_grams: 4000}, change_grams: nil} =
             Puppy.weight_summary(actor: lukas)

    {:ok, _} = Puppy.add_weight(%{weight_grams: 4600, measured_on: ~D[2026-10-08]}, actor: lukas)

    assert %{latest: %{weight_grams: 4600}, previous: %{weight_grams: 4000}, change_grams: 600} =
             Puppy.weight_summary(actor: lukas)
  end

  test "both members can correct and delete any entry", %{lukas: lukas, riv: riv} do
    {:ok, entry} = Puppy.add_weight(%{weight_grams: 4000}, actor: lukas)

    {:ok, entry} =
      Puppy.update_weight(entry, %{weight_grams: 4100, note: "nach dem Fressen"}, actor: riv)

    assert entry.weight_grams == 4100
    assert entry.created_by_id == lukas.id

    assert :ok = Puppy.delete_weight(entry, actor: riv)
    assert Puppy.list_weights!(actor: lukas) == []
  end

  test "rejects implausible values and future dates", %{lukas: lukas} do
    assert {:error, _} = Puppy.add_weight(%{weight_grams: 0}, actor: lukas)
    assert {:error, _} = Puppy.add_weight(%{weight_grams: 500_000}, actor: lukas)

    assert {:error, _} =
             Puppy.add_weight(
               %{weight_grams: 4000, measured_on: Date.add(PuppyLog.Clock.today(), 1)},
               actor: lukas
             )
  end

  test "requires a signed in user" do
    assert {:error, _} = Puppy.add_weight(%{weight_grams: 4000})
  end

  test "deleting a member keeps their entries", %{lukas: lukas} do
    {:ok, entry} = Puppy.add_weight(%{weight_grams: 4000}, actor: lukas)
    %{num_rows: 1} = PuppyLog.Repo.query!("DELETE FROM users WHERE id = ?", [lukas.id])

    assert {:ok, %{created_by_id: nil}} = Puppy.get_weight(entry.id, actor: user_fixture())
  end
end
