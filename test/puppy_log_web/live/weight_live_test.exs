defmodule PuppyLogWeb.WeightLiveTest do
  use PuppyLogWeb.ConnCase, async: false

  alias PuppyLog.Puppy

  setup :register_and_sign_in

  test "adds a weighing with German input", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/gewicht/neu")
    assert has_element?(view, "#weight-sheet[role], #weight-sheet section[role=dialog]")

    view |> form("#weight-form", form: %{weight_kg: "4,35"}) |> render_submit()
    assert_patch(view, ~p"/gewicht")

    # the confirmation toast hides itself, connection notices do not
    assert has_element?(view, ~s{#flash-info[phx-hook="AutoDismiss"]}, "4,35 kg gespeichert")
    refute has_element?(view, ~s{#client-error[phx-hook]})

    assert [%{weight_grams: 4350, created_by_id: id}] = Puppy.list_weights!(actor: user)
    assert id == user.id
    assert render_async(view) =~ "4,35 kg"
  end

  test "shows the change while typing", %{conn: conn, user: user} do
    {:ok, _} = Puppy.add_weight(%{weight_kg: "7,8", measured_on: ~D[2026-11-01]}, actor: user)
    {:ok, view, _html} = live(conn, ~p"/gewicht/neu")

    html = view |> form("#weight-form", form: %{weight_kg: "8,15"}) |> render_change()
    assert html =~ "+350 g seit dem letzten Mal"
  end

  test "explains invalid input", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/gewicht/neu")

    html = view |> form("#weight-form", form: %{weight_kg: "viel"}) |> render_submit()
    assert html =~ "bitte als Zahl eingeben"
  end

  test "edits and deletes entries", %{conn: conn, user: user} do
    {:ok, entry} = Puppy.add_weight(%{weight_kg: "5"}, actor: user)

    {:ok, view, html} = live(conn, ~p"/gewicht/#{entry.id}")
    assert html =~ "Gewicht ändern"

    view |> form("#weight-form", form: %{weight_kg: "5,1"}) |> render_submit()
    assert_patch(view, ~p"/gewicht")
    assert [%{weight_grams: 5100}] = Puppy.list_weights!(actor: user)

    render_async(view)
    view |> element(~s{button[phx-click="delete"][phx-value-id="#{entry.id}"]}) |> render_click()
    assert Puppy.list_weights!(actor: user) == []
  end

  test "lists entries with delta and author, live", %{conn: conn, user: user} do
    {:ok, _} = Puppy.add_weight(%{weight_kg: "4", measured_on: ~D[2026-10-01]}, actor: user)
    {:ok, view, _html} = live(conn, ~p"/gewicht")
    assert render_async(view) =~ "Ab zwei Einträgen"

    riv = user_fixture(%{name: "Riv"})
    {:ok, _} = Puppy.add_weight(%{weight_kg: "4,6", measured_on: ~D[2026-10-08]}, actor: riv)

    html = render_async(view)
    assert html =~ "4,6 kg"
    assert html =~ "+600 g"
    assert html =~ "Riv"
    assert html =~ "Gewichtskurve"
  end
end
