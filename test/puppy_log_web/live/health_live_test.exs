defmodule PuppyLogWeb.HealthLiveTest do
  use PuppyLogWeb.ConnCase, async: false

  alias PuppyLog.Puppy

  doctest PuppyLogWeb.HealthRow

  setup :register_and_sign_in

  setup do
    pin_clock(DateTime.new!(~D[2026-11-13], ~T[10:00:00], "Europe/Berlin"))
    :ok
  end

  defp entry(actor, attrs) do
    Map.merge(%{kind: :other_care, title: "Vorsorge", due_on: ~D[2026-11-20]}, attrs)
    |> Puppy.create_health_entry!(actor: actor)
  end

  test "next card shows the earliest open entry and overdue first", %{conn: conn, user: user} do
    riv = user_fixture(%{name: "Riv"})
    entry(user, %{title: "Fellpflege", due_on: ~D[2026-11-13]})

    entry(user, %{
      kind: :vet_visit,
      title: "Kontrolle",
      due_on: ~D[2026-11-13],
      due_time: ~T[08:00:00],
      location: "Praxis Klein",
      assignee_id: riv.id
    })

    entry(user, %{title: "Entwurmung", due_on: ~D[2026-11-20], status: :done})

    {:ok, view, _html} = live(conn, ~p"/health")

    assert has_element?(view, "#health-next", "Kontrolle")
    assert has_element?(view, "#health-next", "überfällig")
    assert has_element?(view, "#health-next", "08:00 · Praxis Klein")
    assert has_element?(view, "#health-next", "Geht hin: Riv")
    refute has_element?(view, "#health-next", "Fellpflege")
  end

  test "next card counts the days until the next entry", %{conn: conn, user: user} do
    entry(user, %{title: "Nachimpfung", kind: :vaccination, due_on: ~D[2026-11-20]})
    entry(user, %{title: "Entwurmung", due_on: ~D[2026-12-01]})

    {:ok, view, _html} = live(conn, ~p"/health")

    assert has_element?(view, "#health-next", "in 7 Tagen")
    assert has_element?(view, "#health-next", "Nachimpfung")
  end

  test "no open entries shows the hint", %{conn: conn, user: user} do
    entry(user, %{title: "Entwurmung", due_on: ~D[2026-11-01], status: :done})

    {:ok, view, _html} = live(conn, ~p"/health")

    assert has_element?(view, "#health-next", "Keine offenen Termine")
    assert has_element?(view, ~s{#health-next a[href="/health/new"]}, "Termin eintragen")
  end

  test "list shows chips (Überfällig, In 2 Tagen, Erledigt)", %{conn: conn, user: user} do
    late = entry(user, %{title: "Floh und Zecke", kind: :flea_tick, due_on: ~D[2026-11-11]})
    soon = entry(user, %{title: "Nachimpfung", due_on: ~D[2026-11-15], remind_days_before: 3})

    done =
      entry(user, %{
        title: "Grundimmunisierung",
        kind: :vaccination,
        due_on: ~D[2026-10-28],
        status: :done,
        done_on: ~D[2026-10-28],
        batch: "A123"
      })

    {:ok, view, _html} = live(conn, ~p"/health")
    render_async(view)

    assert has_element?(view, "#health-#{late.id}", "Überfällig")
    assert has_element?(view, "#health-#{soon.id}", "In 2 Tagen")
    assert has_element?(view, "#health-#{done.id}", "Erledigt")
    assert has_element?(view, "#health-#{done.id}", "28.10.")
    assert has_element?(view, "#health-#{done.id}", "A123")
    assert has_element?(view, ~s{#health-#{soon.id} a[href="/health/#{soon.id}"]})
  end

  test "complete via sheet with batch creates the successor and flashes its date",
       %{conn: conn, user: user} do
    vaccination =
      entry(user, %{title: "Tollwut", kind: :vaccination, due_on: ~D[2026-11-13], repeat_weeks: 4})

    {:ok, view, _html} = live(conn, ~p"/health")
    render_async(view)

    view
    |> element(~s{#health-#{vaccination.id} [phx-click*="/health/#{vaccination.id}/done"]})
    |> render_click()

    assert_patch(view, ~p"/health/#{vaccination.id}/done")
    assert has_element?(view, "#health-sheet", "Impfstoff/Charge")

    view
    |> form("#health-complete-form", complete: %{done_on: "2026-11-12", batch: "B77"})
    |> render_submit()

    assert_patch(view, ~p"/health")
    assert has_element?(view, "#flash-info", "Erledigt. Nächster Termin am 10. Dezember 2026.")

    assert {:ok, %{status: :done, done_on: ~D[2026-11-12], batch: "B77"}} =
             Puppy.get_health_entry(vaccination.id, actor: user)

    assert Enum.any?(
             Puppy.list_health_entries!(actor: user),
             &(&1.previous_id == vaccination.id and &1.due_on == ~D[2026-12-10])
           )
  end

  test "complete without repetition flashes Erledigt and rejects a future date",
       %{conn: conn, user: user} do
    care = entry(user, %{title: "Krallen", due_on: ~D[2026-11-13]})

    {:ok, view, _html} = live(conn, ~p"/health/#{care.id}/done")
    refute has_element?(view, "#health-sheet", "Impfstoff/Charge")

    view
    |> form("#health-complete-form", complete: %{done_on: "2026-11-20"})
    |> render_submit()

    assert has_element?(view, "#flash-error", "Darf nicht in der Zukunft liegen")
    assert {:ok, %{status: :open}} = Puppy.get_health_entry(care.id, actor: user)

    view
    |> form("#health-complete-form", complete: %{done_on: "2026-11-13"})
    |> render_submit()

    assert_patch(view, ~p"/health")
    assert has_element?(view, "#flash-info", "Erledigt.")
    assert {:ok, %{status: :done}} = Puppy.get_health_entry(care.id, actor: user)
  end

  test "an unknown or finished entry closes the sheet", %{conn: conn, user: user} do
    assert {:error, {:live_redirect, %{to: "/health", flash: flash}}} =
             live(conn, ~p"/health/#{Ecto.UUID.generate()}/done")

    assert flash["error"] == "Diesen Eintrag gibt es nicht mehr."

    done = entry(user, %{title: "Krallen", due_on: ~D[2026-11-10], status: :done})
    {:ok, view, _html} = live(conn, ~p"/health")
    render_async(view)
    render_patch(view, ~p"/health/#{done.id}/done")

    assert_patch(view, ~p"/health")
    assert has_element?(view, "#flash-error", "Schon erledigt")
    refute has_element?(view, "#health-sheet")
  end

  test "reopen from the swipe action", %{conn: conn, user: user} do
    done = entry(user, %{title: "Entwurmung", due_on: ~D[2026-11-10], status: :done})

    {:ok, view, _html} = live(conn, ~p"/health")
    render_async(view)

    view
    |> element(~s{button[phx-click="reopen"][phx-value-id="#{done.id}"]})
    |> render_click()

    assert {:ok, %{status: :open}} = Puppy.get_health_entry(done.id, actor: user)
    assert has_element?(view, "#flash-info", "Wieder offen.")
    assert has_element?(view, "#health-#{done.id}", "Überfällig")
  end

  test "live update when the other member adds an entry", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/health")
    assert has_element?(view, "#health-next", "Keine offenen Termine")

    riv = user_fixture(%{name: "Riv"})
    entry(riv, %{title: "Wurmkur", kind: :deworming, due_on: ~D[2026-11-16]})

    assert render_async(view) =~ "Wurmkur"
    assert has_element?(view, "#health-next", "Wurmkur")
    assert has_element?(view, "#health-next", "in 3 Tagen")
  end
end
