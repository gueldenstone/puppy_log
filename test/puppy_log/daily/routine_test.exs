defmodule PuppyLog.Daily.RoutineTest do
  use PuppyLog.DataCase, async: false

  alias PuppyLog.Daily

  setup do
    %{lukas: user_fixture(%{name: "Lukas"}), riv: user_fixture(%{name: "Riv"})}
  end

  defp attrs(extra \\ %{}) do
    Map.merge(
      %{name: "Mittagsschlaf", kind: :sleep, starts_at: ~T[12:30:00], ends_at: ~T[14:00:00]},
      extra
    )
  end

  test "creates a window routine with assignee and creator", %{lukas: lukas, riv: riv} do
    {:ok, routine} =
      Daily.create_routine(attrs(%{weekdays: [1, 2, 3, 4, 5], assignee_id: riv.id}),
        actor: lukas
      )

    assert routine.name == "Mittagsschlaf"
    assert routine.kind == :sleep
    assert routine.starts_at == ~T[12:30:00]
    assert routine.ends_at == ~T[14:00:00]
    assert routine.weekdays == [1, 2, 3, 4, 5]
    assert routine.assignee_id == riv.id
    assert routine.remind? == true
    assert routine.created_by_id == lukas.id
  end

  test "rejects a window ending before it starts", %{lukas: lukas} do
    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             Daily.create_routine(attrs(%{ends_at: ~T[12:00:00]}), actor: lukas)

    assert Enum.any?(errors, &(&1.field == :ends_at))
  end

  test "rejects empty or invalid weekdays", %{lukas: lukas} do
    assert {:error, %Ash.Error.Invalid{}} =
             Daily.create_routine(attrs(%{weekdays: []}), actor: lukas)

    assert {:error, %Ash.Error.Invalid{}} =
             Daily.create_routine(attrs(%{weekdays: [0, 8]}), actor: lukas)
  end

  test "archived routines disappear from the active list", %{lukas: lukas} do
    {:ok, routine} = Daily.create_routine(attrs(), actor: lukas)
    assert [_] = Daily.list_routines!(actor: lukas)

    {:ok, archived} = Daily.archive_routine(routine, actor: lukas)
    assert archived.archived_at

    assert Daily.list_routines!(actor: lukas) == []
    assert Daily.get_routine!(routine.id, actor: lukas).id == routine.id
  end

  test "lists active routines sorted by start time", %{lukas: lukas} do
    {:ok, _} =
      Daily.create_routine(attrs(%{name: "B", starts_at: ~T[18:00:00], ends_at: nil}),
        actor: lukas
      )

    {:ok, _} =
      Daily.create_routine(attrs(%{name: "A", starts_at: ~T[07:00:00], ends_at: nil}),
        actor: lukas
      )

    assert Enum.map(Daily.list_routines!(actor: lukas), & &1.name) == ["A", "B"]
  end

  test "requires a signed in user" do
    assert {:error, _} = Daily.create_routine(attrs())
  end
end
