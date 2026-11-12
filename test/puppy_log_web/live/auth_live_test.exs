defmodule PuppyLogWeb.AuthLiveTest do
  use PuppyLogWeb.ConnCase, async: false

  alias PuppyLog.Accounts.MagicLinks
  alias PuppyLogWeb.SignInLive

  test "the home page requires a signed in user", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, ~p"/")
  end

  test "pasting a login link opens the confirmation page", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/sign-in")
    assert html =~ "Login-Link"

    token = "aaa.bbb.ccc"

    assert {:error, {:live_redirect, %{to: "/magic_link/aaa.bbb.ccc"}}} =
             view
             |> form("#login-link-form", login: %{link: "https://x.example/magic_link/#{token}"})
             |> render_submit()
  end

  test "invalid input shows an error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/sign-in")

    assert view
           |> form("#login-link-form", login: %{link: "hallo"})
           |> render_submit() =~ "sieht nicht wie ein Login-Link aus"
  end

  test "extract_token accepts URLs and bare tokens" do
    assert {:ok, "a.b.c"} = SignInLive.extract_token("  https://p.example/magic_link/a.b.c  ")
    assert {:ok, "a.b.c"} = SignInLive.extract_token("a.b.c")
    assert :error = SignInLive.extract_token("https://p.example/")
  end

  test "magic link signs in and keeps the device signed in", %{conn: conn} do
    {:ok, _user} = MagicLinks.create_user("lisa@example.com", "Lisa")
    {:ok, url} = MagicLinks.url_for("lisa@example.com")
    path = URI.parse(url).path
    [_, token] = String.split(path, "/magic_link/")

    {:ok, _view, html} = live(conn, path)
    assert html =~ "Anmelden"
    assert html =~ token

    conn =
      post(conn, ~p"/auth/user/magic_link", %{
        "user" => %{"token" => token, "remember_me" => "true"}
      })

    assert redirected_to(conn) == "/"
    assert conn.resp_cookies["remember_me"].max_age > 300 * 24 * 3600

    {:ok, _view, html} = conn |> recycle() |> live(~p"/")
    assert html =~ "Welpenprofil anlegen"
    assert html =~ "Lisa"
  end

  test "an invalid magic link redirects back to sign in", %{conn: conn} do
    conn = post(conn, ~p"/auth/user/magic_link", %{"user" => %{"token" => "nope"}})
    assert redirected_to(conn) == "/sign-in"
  end
end
