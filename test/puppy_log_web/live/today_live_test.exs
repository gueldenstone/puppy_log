defmodule PuppyLogWeb.TodayLiveTest do
  use PuppyLogWeb.ConnCase, async: false

  alias PuppyLog.Puppy

  setup :register_and_sign_in

  test "asks to create the profile first", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Welpenprofil anlegen"

    assert has_element?(
             view,
             ~s{nav[aria-label="Hauptnavigation"] a[aria-current="page"]},
             "Heute"
           )
  end

  test "shows name, age and latest weight", %{conn: conn, user: user} do
    birth = Date.add(PuppyLog.Clock.today(), -14 * 7)
    {:ok, _} = Puppy.create_profile(%{name: "Bruno", birth_date: birth}, actor: user)
    {:ok, _} = Puppy.add_weight(%{weight_kg: "7,8"}, actor: user)

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Bruno"
    assert html =~ "14 Wochen · 7,8 kg"
    refute html =~ "Welpenprofil anlegen"
  end

  test "updates live when the other person weighs", %{conn: conn, user: user} do
    {:ok, _} = Puppy.create_profile(%{name: "Bruno"}, actor: user)
    {:ok, view, _html} = live(conn, ~p"/")

    riv = user_fixture(%{name: "Riv"})
    {:ok, _} = Puppy.add_weight(%{weight_kg: "5,25"}, actor: riv)

    assert render(view) =~ "5,25 kg"
  end

  test "household avatars link to the settings", %{conn: conn} do
    user_fixture(%{name: "Riv"})
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ~s{a[href="/einstellungen"][aria-label*="Riv"]})
  end
end
