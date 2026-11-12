defmodule PuppyLogWeb.SettingsLiveTest do
  use PuppyLogWeb.ConnCase, async: false

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
    {:ok, view, _html} = live(conn, ~p"/einstellungen")

    assert has_element?(view, "#member-#{user.id}", "Keine Mitteilungen aktiviert")
    assert has_element?(view, "#member-#{riv.id}", "1 Gerät · Mitteilungen aktiv")
  end

  test "asks to add the app to the home screen in Safari", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/einstellungen")

    assert render_hook(view, "device_status", %{@iphone_status | "standalone" => false}) =~
             "Zum Home-Bildschirm"
  end

  test "registers this device", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/einstellungen")
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

    {:ok, view, _html} = live(conn, ~p"/einstellungen")
    view |> element("button[phx-value-target='me'][phx-value-delay='0']") |> render_click()

    assert render_async(view) =~ "1 von 1 an den Push-Dienst übergeben"
  end
end
