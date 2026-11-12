defmodule PuppyLog.Daily.SettingsTest do
  use PuppyLog.DataCase, async: false

  alias PuppyLog.{Accounts, Daily}

  setup do
    %{lukas: user_fixture(%{name: "Lukas"}), riv: user_fixture(%{name: "Riv"})}
  end

  test "returns defaults without a stored row", %{lukas: lukas} do
    settings = Daily.settings(actor: lukas)
    assert settings.quiet_hours_enabled == false
    assert settings.quiet_from == ~T[22:00:00]
    assert settings.quiet_until == ~T[06:30:00]
  end

  test "saving twice keeps a single row", %{lukas: lukas} do
    {:ok, _} = Daily.save_settings(%{quiet_hours_enabled: true}, actor: lukas)
    {:ok, _} = Daily.save_settings(%{quiet_from: ~T[21:00:00]}, actor: lukas)

    assert [_] = Ash.read!(PuppyLog.Daily.Settings, actor: lukas)
    settings = Daily.settings(actor: lukas)
    assert settings.quiet_hours_enabled == true
    assert settings.quiet_from == ~T[21:00:00]
  end

  test "a member can switch reminders off", %{lukas: lukas, riv: riv} do
    assert riv.receives_reminders == true

    assert {:ok, user} = Accounts.set_reminders(riv, %{receives_reminders: false}, actor: lukas)
    assert user.receives_reminders == false
  end

  test "set_reminders requires an actor", %{riv: riv} do
    assert {:error, _} = Accounts.set_reminders(riv, %{receives_reminders: false})
  end
end
