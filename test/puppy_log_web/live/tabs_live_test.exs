defmodule PuppyLogWeb.TabsLiveTest do
  use PuppyLogWeb.ConnCase, async: false

  alias PuppyLog.Puppy

  setup :register_and_sign_in

  test "Gesundheit shows the weight card", %{conn: conn, user: user} do
    {:ok, _view, html} = live(conn, ~p"/health")
    assert html =~ "Noch nicht gewogen"

    {:ok, _} = Puppy.add_weight(%{weight_kg: "4", measured_on: ~D[2026-10-01]}, actor: user)
    {:ok, _} = Puppy.add_weight(%{weight_kg: "4,6", measured_on: ~D[2026-10-08]}, actor: user)

    {:ok, _view, html} = live(conn, ~p"/health")
    assert html =~ "4,6 kg"
    assert html =~ "+600 g seit Do, 1. Okt"
  end

  test "Verlauf and Lernen are announced", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/history")
    assert html =~ "Verlauf"

    {:ok, _view, html} = live(conn, ~p"/learn")
    assert html =~ "Sozialisierung und Kommandos"
  end
end
