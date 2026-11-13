defmodule PuppyLogWeb.SettingsLiveTest do
  use PuppyLogWeb.ConnCase, async: false

  alias PuppyLog.{Accounts, Daily}
  alias PuppyLog.Notifications.Push

  setup :register_and_sign_in

  @iphone_status %{
    "ios" => true,
    "standalone" => true,
    "sw" => true,
    "push" => true,
    "permission" => "default",
    "subscribed" => false,
    "endpoint" => nil,
    "error" => nil,
    "user_agent" => "iPhone"
  }

  test "lists household members with their devices", %{conn: conn, user: user} do
    riv = user_fixture(%{name: "Riv"})
    subscription_fixture(riv)
    {:ok, view, _html} = live(conn, ~p"/settings")

    assert has_element?(view, "#member-#{user.id}", "Keine Mitteilungen aktiviert")
    assert has_element?(view, "#member-#{riv.id}", "1 Gerät · Mitteilungen aktiv")
  end

  test "asks to add the app to the home screen in Safari", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    assert render_hook(view, "device_status", %{@iphone_status | "standalone" => false}) =~
             "Zum Home-Bildschirm"
  end

  test "registers this device", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/settings")
    assert render_hook(view, "device_status", @iphone_status) =~ "Mitteilungen erlauben"

    keys = browser_keys()

    render_hook(view, "subscribed", %{
      "subscription" => %{
        "endpoint" => "https://web.push.apple.com/abc",
        "keys" => %{"p256dh" => keys.p256dh, "auth" => keys.auth_b64}
      },
      "user_agent" => "iPhone"
    })

    assert has_element?(view, "#member-#{user.id}", "1 Gerät · Mitteilungen aktiv")
  end

  test "sends a test push and shows the result", %{conn: conn, user: user} do
    subscription_fixture(user)
    Req.Test.stub(Push, &Plug.Conn.send_resp(&1, 201, ""))

    {:ok, view, _html} = live(conn, ~p"/settings")
    view |> element("button[phx-value-target='me'][phx-value-delay='0']") |> render_click()

    assert render_async(view) =~ "1 von 1 an den Push-Dienst übergeben"
  end

  test "turns off reminders for Riv", %{conn: conn, user: user} do
    riv = user_fixture(%{name: "Riv"})
    {:ok, view, _html} = live(conn, ~p"/settings")

    assert has_element?(view, ~s{#member-#{riv.id} input[role="switch"][checked]})

    view |> element(~s{#member-#{riv.id} input[role="switch"]}) |> render_click()

    refute has_element?(view, ~s{#member-#{riv.id} input[role="switch"][checked]})
    assert has_element?(view, ~s{#member-#{user.id} input[role="switch"][checked]})

    users = Accounts.list_users!(actor: user)
    assert %{receives_reminders: false} = Enum.find(users, &(&1.id == riv.id))
    assert %{receives_reminders: true} = Enum.find(users, &(&1.id == user.id))
  end

  test "saves quiet hours 22:00–06:30", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/settings")
    html = render(view)
    assert html =~ "In dieser Zeit gibt es keine Erinnerungen."
    # quiet hours drop reminders, they are not sent afterwards (spec)
    assert html =~ "Erinnerungen fallen aus, nichts wird nachgeholt"
    refute html =~ "danach nachgeholt"

    view
    |> form("#quiet-hours-form",
      settings: %{quiet_hours_enabled: "true", quiet_from: "21:00", quiet_until: "07:00"}
    )
    |> render_change()

    view
    |> form("#quiet-hours-form", settings: %{quiet_from: "22:00", quiet_until: "06:30"})
    |> render_change()

    assert %{quiet_hours_enabled: true, quiet_from: ~T[22:00:00], quiet_until: ~T[06:30:00]} =
             Daily.settings(actor: user)

    assert has_element?(view, ~s{input[name="settings[quiet_from]"][value="22:00"]})
  end

  test "links to the routines", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings")

    assert has_element?(view, ~s{a[href="/routines"]}, "Routinen verwalten")
  end
end
