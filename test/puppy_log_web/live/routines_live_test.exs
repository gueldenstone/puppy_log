defmodule PuppyLogWeb.RoutinesLiveTest do
  use PuppyLogWeb.ConnCase, async: false

  alias PuppyLog.{Clock, Daily, Puppy}
  alias PuppyLogWeb.Format

  setup :register_and_sign_in

  test "lists active routines by time with schedule, assignee and reminder", %{
    conn: conn,
    user: user
  } do
    riv = user_fixture(%{name: "Riv"})
    routine(user, %{name: "Mittagessen", kind: :meal, starts_at: ~T[13:00:00]})

    routine(user, %{
      name: "Training",
      kind: :training,
      starts_at: ~T[09:00:00],
      ends_at: ~T[11:00:00],
      weekdays: [1, 2, 3, 4, 5],
      assignee_id: riv.id,
      remind?: false
    })

    {:ok, view, _html} = live(conn, ~p"/routines")
    html = render_async(view)

    assert has_element?(view, ~s{header a[href="/settings"]})
    assert html =~ "09:00 bis 11:00 · Mo–Fr"
    assert html =~ "13:00 · täglich"
    assert html =~ ~r/Training.*Mittagessen/s
    assert has_element?(view, "a", "Riv")
    assert has_element?(view, "a span", "aus")
    assert has_element?(view, ~s{a[href="/routines/new"]}, "Neue Routine")
  end

  test "creates a window routine with weekdays and assignee", %{conn: conn, user: user} do
    riv = user_fixture(%{name: "Riv"})
    {:ok, view, _html} = live(conn, ~p"/routines/new")

    view |> form("#routine-form", mode: "window") |> render_change()

    {:ok, list, _html} =
      view
      |> form("#routine-form",
        form: %{
          name: "Mittagsschlaf",
          kind: "sleep",
          starts_at: "12:30",
          ends_at: "14:00",
          weekdays: ~w(1 2 3 4 5),
          assignee_id: riv.id
        }
      )
      |> render_submit()
      |> follow_redirect(conn, ~p"/routines")

    html = render_async(list)
    assert html =~ "Mittagsschlaf"
    assert html =~ "12:30 bis 14:00 · Mo–Fr"
    assert html =~ "Riv"
    assert html =~ "Routine gespeichert"

    assert [routine] = Daily.list_routines!(actor: user)
    assert %{kind: :sleep, weekdays: [1, 2, 3, 4, 5], assignee_id: assignee_id} = routine
    assert assignee_id == riv.id
    assert routine.created_by_id == user.id
  end

  test "shows a validation message for an inverted window", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/routines/new")
    view |> form("#routine-form", mode: "window") |> render_change()

    html =
      view
      |> form("#routine-form",
        form: %{name: "Schlaf", kind: "sleep", starts_at: "14:00", ends_at: "12:30"}
      )
      |> render_submit()

    assert html =~ "muss nach dem Beginn liegen"
  end

  test "a fixed time drops the window end and follow-up off clears the minutes", %{
    conn: conn,
    user: user
  } do
    existing =
      routine(user, %{
        name: "Training",
        kind: :training,
        starts_at: ~T[09:00:00],
        ends_at: ~T[11:00:00],
        follow_up_minutes: 30
      })

    {:ok, view, _html} = live(conn, ~p"/routines/#{existing.id}")
    assert has_element?(view, "h1", "Routine bearbeiten")
    assert has_element?(view, ~s{select[name="form[follow_up_minutes]"] option[selected]}, "30")

    view |> form("#routine-form", mode: "fixed", follow_up: "false") |> render_change()
    refute has_element?(view, ~s{input[name="form[ends_at]"]})

    {:ok, _list, _html} =
      view
      |> form("#routine-form", form: %{starts_at: "10:00"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/routines")

    assert {:ok, %{starts_at: ~T[10:00:00], ends_at: nil, follow_up_minutes: nil}} =
             Daily.get_routine(existing.id, actor: user)
  end

  test "offers 15, 30, 45 and 60 minutes for the follow-up", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/routines/new")
    view |> form("#routine-form", follow_up: "true") |> render_change()

    options = view |> element(~s{select[name="form[follow_up_minutes]"]}) |> render()

    assert Regex.scan(~r/<option[^>]*value="(\d*)"/, options, capture: :all_but_first) ==
             [["15"], ["30"], ["45"], ["60"]]
  end

  test "asks for the kind when it was not chosen", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/routines/new")

    html =
      view
      |> form("#routine-form", form: %{name: "Pipi-Runde", starts_at: "10:00"})
      |> render_submit()

    assert html =~ "Bitte wählen, wodurch die Routine erledigt wird."
    assert Daily.list_routines!(actor: user) == []
  end

  test "keeps a stored follow-up outside the usual choices", %{conn: conn, user: user} do
    existing =
      routine(user, %{
        name: "Training",
        kind: :training,
        starts_at: ~T[09:00:00],
        follow_up_minutes: 20
      })

    {:ok, view, _html} = live(conn, ~p"/routines/#{existing.id}")
    assert has_element?(view, ~s{select[name="form[follow_up_minutes]"] option[selected]}, "20")

    {:ok, _list, _html} =
      view
      |> form("#routine-form", form: %{name: "Training kurz"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/routines")

    assert {:ok, %{name: "Training kurz", follow_up_minutes: 20}} =
             Daily.get_routine(existing.id, actor: user)
  end

  test "archives a routine", %{conn: conn, user: user} do
    existing = routine(user, %{name: "Pipi-Runde", kind: :potty, starts_at: ~T[10:00:00]})
    {:ok, view, _html} = live(conn, ~p"/routines/#{existing.id}")

    assert has_element?(
             view,
             ~s{button[data-confirm="Diese Routine löschen? Der Verlauf bleibt erhalten."]},
             "Routine löschen"
           )

    {:ok, list, _html} =
      view
      |> element("button", "Routine löschen")
      |> render_click()
      |> follow_redirect(conn, ~p"/routines")

    html = render_async(list)
    assert html =~ "Routine gelöscht"
    refute has_element?(list, "#routine-#{existing.id}")
    assert Daily.list_routines!(actor: user) == []
  end

  test "routines can be set up before the puppy moves in", %{conn: conn, user: user} do
    {:ok, _} =
      Puppy.create_profile(%{name: "Bruno", arrival_date: Date.add(Clock.today(), 10)},
        actor: user
      )

    {:ok, view, _html} = live(conn, ~p"/routines/new")

    {:ok, list, _html} =
      view
      |> form("#routine-form", form: %{name: "Frühstück", kind: "meal", starts_at: "07:30"})
      |> render_submit()
      |> follow_redirect(conn, ~p"/routines")

    assert render_async(list) =~ "07:30 · täglich"
  end

  test "an unknown routine goes back to the list", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/routines"}}} =
             live(conn, ~p"/routines/#{Ecto.UUID.generate()}")
  end

  test "summarises weekdays" do
    assert Format.weekdays([1, 2, 3, 4, 5, 6, 7]) == "täglich"
    assert Format.weekdays([1, 2, 3, 4, 5]) == "Mo–Fr"
    assert Format.weekdays([6, 7]) == "Sa, So"
    assert Format.weekdays([5, 1, 3]) == "Mo, Mi, Fr"
  end

  defp routine(user, attrs) do
    {:ok, routine} = Daily.create_routine(attrs, actor: user)
    routine
  end
end
