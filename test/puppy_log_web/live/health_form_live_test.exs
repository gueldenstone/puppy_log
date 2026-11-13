defmodule PuppyLogWeb.HealthFormLiveTest do
  use PuppyLogWeb.ConnCase, async: false

  alias PuppyLog.{Daily, Puppy}

  setup :register_and_sign_in

  setup do
    pin_clock(DateTime.new!(~D[2026-11-13], ~T[10:00:00], "Europe/Berlin"))
    :ok
  end

  defp entry(actor, attrs) do
    Map.merge(%{kind: :other_care, title: "Vorsorge", due_on: ~D[2026-11-20]}, attrs)
    |> Puppy.create_health_entry!(actor: actor)
  end

  defp choose_kind(view, kind) do
    view |> form("#health-form", form: %{kind: kind}) |> render_change()
  end

  defp save(view, conn, params) do
    {:ok, list, _html} =
      view
      |> form("#health-form", params)
      |> render_submit()
      |> follow_redirect(conn, ~p"/health")

    list
  end

  test "creates a vaccination with repetition", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/health/new")
    assert has_element?(view, "h1", "Termin eintragen")

    for label <- ["Impfung", "Entwurmung", "Floh/Zecke", "Andere Vorsorge", "Tierarzt"],
        do: assert(has_element?(view, "#health-form label", label))

    choose_kind(view, "vaccination")
    assert has_element?(view, "label", "Fällig am")
    assert has_element?(view, ~s{input[name="form[batch]"]})
    refute has_element?(view, "#health-repeat-weeks")

    view |> form("#health-form", repeat: "true") |> render_change()
    assert has_element?(view, "#health-repeat-weeks", "Alle 4 Wochen")

    view |> element("#health-repeat-weeks button[aria-label='mehr']") |> render_click()
    assert has_element?(view, "#health-repeat-weeks", "Alle 5 Wochen")

    list =
      save(view, conn,
        form: %{title: "Tollwut", due_on: "2026-12-01", batch: "AB12", notes: "Impfpass mit"}
      )

    assert render_async(list) =~ "Gespeichert."

    assert [saved] = Puppy.list_health_entries!(actor: user)

    assert %{
             kind: :vaccination,
             title: "Tollwut",
             due_on: ~D[2026-12-01],
             repeat_weeks: 5,
             batch: "AB12",
             notes: "Impfpass mit",
             status: :open
           } = saved

    assert saved.created_by_id == user.id
  end

  test "vet visit requires time and offers place and assignee", %{conn: conn, user: user} do
    riv = user_fixture(%{name: "Riv"})
    {:ok, view, _html} = live(conn, ~p"/health/new")

    refute has_element?(view, ~s{input[name="form[due_time]"]})
    choose_kind(view, "vet_visit")

    assert has_element?(view, "label", "Datum")
    assert has_element?(view, "label", "Uhrzeit")
    assert has_element?(view, ~s{input[name="form[location]"]})
    assert has_element?(view, ~s{select[name="form[assignee_id]"] option}, "Riv")
    refute has_element?(view, "#health-repeat-weeks")
    refute has_element?(view, ~s{input[name="repeat"]})
    refute has_element?(view, ~s{input[name="form[batch]"]})

    html =
      view
      |> form("#health-form", form: %{title: "Kontrolle", due_on: "2026-11-20"})
      |> render_submit()

    assert html =~ "Bitte eine Uhrzeit angeben"
    assert Puppy.list_health_entries!(actor: user) == []

    save(view, conn,
      form: %{
        title: "Kontrolle",
        due_on: "2026-11-20",
        due_time: "09:30",
        location: "Praxis Dr. Berg",
        assignee_id: riv.id
      }
    )

    assert [saved] = Puppy.list_health_entries!(actor: user)

    assert %{kind: :vet_visit, due_time: ~T[09:30:00], location: "Praxis Dr. Berg"} = saved
    assert saved.assignee_id == riv.id
  end

  test "asks for the kind when it was not chosen", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/health/new")

    html =
      view
      |> form("#health-form", form: %{title: "Etwas", due_on: "2026-11-20"})
      |> render_submit()

    assert html =~ "Bitte eine Art wählen."
    assert Puppy.list_health_entries!(actor: user) == []
  end

  test "switching kind hides vet-only fields", %{conn: conn, user: user} do
    vet =
      entry(user, %{
        kind: :vet_visit,
        title: "Kontrolle",
        due_time: ~T[09:30:00],
        location: "Praxis Dr. Berg",
        assignee_id: user.id
      })

    {:ok, view, _html} = live(conn, ~p"/health/#{vet.id}")
    assert has_element?(view, ~s{input[name="form[due_time]"][value="09:30"]})

    choose_kind(view, "deworming")
    refute has_element?(view, ~s{input[name="form[due_time]"]})
    refute has_element?(view, ~s{input[name="form[location]"]})
    refute has_element?(view, ~s{select[name="form[assignee_id]"]})
    refute has_element?(view, ~s{input[name="form[batch]"]})
    assert has_element?(view, "label", "Fällig am")

    save(view, conn, form: %{title: "Entwurmung"})

    assert {:ok, %{kind: :deworming, due_time: nil, location: nil, assignee_id: nil}} =
             Puppy.get_health_entry(vet.id, actor: user)

    vaccination =
      entry(user, %{kind: :vaccination, title: "Impfung", batch: "AB12", repeat_weeks: 4})

    {:ok, view, _html} = live(conn, ~p"/health/#{vaccination.id}")
    assert has_element?(view, "#health-repeat-weeks", "Alle 4 Wochen")

    choose_kind(view, "vet_visit")
    save(view, conn, form: %{due_time: "11:00"})

    assert {:ok, %{kind: :vet_visit, batch: nil, repeat_weeks: nil, due_time: ~T[11:00:00]}} =
             Puppy.get_health_entry(vaccination.id, actor: user)
  end

  test "enter a past vaccination as done creates its successor", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/health/new")
    choose_kind(view, "vaccination")
    view |> form("#health-form", repeat: "true", done: "true") |> render_change()

    assert has_element?(view, ~s{input[name="form[done_on]"][value="2026-11-13"]})
    assert has_element?(view, "label", "Erledigt am")

    save(view, conn,
      form: %{title: "Grundimmunisierung", due_on: "2026-10-01", done_on: "2026-10-01"}
    )

    assert [successor, done] = Puppy.list_health_entries!(actor: user)
    assert %{status: :done, done_on: ~D[2026-10-01], repeat_weeks: 4} = done
    assert %{status: :open, due_on: ~D[2026-10-29], previous_id: previous_id} = successor
    assert previous_id == done.id
  end

  test "edit and delete", %{conn: conn, user: user} do
    existing = entry(user, %{title: "Fellpflege", remind_days_before: 3})

    {:ok, view, _html} = live(conn, ~p"/health/#{existing.id}")
    assert has_element?(view, "h1", "Eintrag bearbeiten")
    assert has_element?(view, ~s{input[name="form[title]"][value="Fellpflege"]})
    assert has_element?(view, "#health-remind", "3 Tage vorher")
    refute has_element?(view, ~s{input[name="done"]})

    list = save(view, conn, form: %{title: "Krallen schneiden", due_on: "2026-11-25"})
    assert render_async(list) =~ "Gespeichert."

    assert {:ok, %{title: "Krallen schneiden", due_on: ~D[2026-11-25]}} =
             Puppy.get_health_entry(existing.id, actor: user)

    {:ok, view, _html} = live(conn, ~p"/health/#{existing.id}")

    assert has_element?(
             view,
             ~s{button[data-confirm="Diesen Eintrag löschen?"]},
             "Eintrag löschen"
           )

    {:ok, _list, _html} =
      view
      |> element("button", "Eintrag löschen")
      |> render_click()
      |> follow_redirect(conn, ~p"/health")

    assert Puppy.list_health_entries!(actor: user) == []
  end

  test "unknown id redirects with flash", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/health", flash: flash}}} =
             live(conn, ~p"/health/#{Ecto.UUID.generate()}")

    assert flash["error"] == "Diesen Eintrag gibt es nicht mehr."
  end

  test "default lead time comes from settings", %{conn: conn, user: user} do
    {:ok, _} = Daily.save_settings(%{health_reminder_days: 2}, actor: user)

    {:ok, view, _html} = live(conn, ~p"/health/new")
    assert has_element?(view, "#health-remind", "2 Tage vorher")
    assert render(view) =~ "Die Erinnerung kommt über euer Kalender-Abo."

    view |> element("#health-remind button[aria-label='weniger']") |> render_click()
    assert has_element?(view, "#health-remind", "1 Tag vorher")
    view |> element("#health-remind button[aria-label='weniger']") |> render_click()
    assert has_element?(view, "#health-remind", "Am Tag selbst")
    assert has_element?(view, "#health-remind button[aria-label='weniger'][disabled]")

    choose_kind(view, "other_care")
    save(view, conn, form: %{title: "Ohren putzen", due_on: "2026-11-20"})

    assert [%{remind_days_before: 0}] = Puppy.list_health_entries!(actor: user)

    {:ok, _} = Daily.save_settings(%{health_reminder_days: 5}, actor: user)
    {:ok, view, _html} = live(conn, ~p"/health/new")
    assert has_element?(view, "#health-remind", "5 Tage vorher")
  end

  test "the completion sheet route still opens the sheet", %{conn: conn, user: user} do
    open = entry(user, %{title: "Entwurmung"})

    {:ok, view, _html} = live(conn, ~p"/health/#{open.id}/done")
    assert has_element?(view, "#health-sheet", "Entwurmung")
    assert has_element?(view, "#health-complete-form")
  end

  describe "due at an age" do
    setup %{user: user} do
      {:ok, _} = Puppy.create_profile(%{name: "Momo", birth_date: ~D[2026-10-07]}, actor: user)
      :ok
    end

    defp choose_mode(view, mode) do
      view |> form("#health-form", due_mode: mode) |> render_change()
    end

    test "care kinds offer Datum or Alter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/health/new")

      assert has_element?(view, ~s{[role="radiogroup"][aria-label="Fällig"] label}, "Datum")
      assert has_element?(view, ~s{[role="radiogroup"][aria-label="Fällig"] label}, "Alter")

      choose_kind(view, "vet_visit")
      refute has_element?(view, ~s{[role="radiogroup"][aria-label="Fällig"]})
    end

    test "entering an age shows the computed date and saves it", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/health/new")
      choose_kind(view, "vaccination")
      choose_mode(view, "age")

      view
      |> form("#health-form", form: %{due_age: "8", due_age_unit: "weeks"})
      |> render_change()

      assert has_element?(view, "#health-due-age-preview", "→ Mi, 2. Dez")

      save(view, conn, form: %{title: "ZZ Impfung"})

      assert [%{due_age: 8, due_age_unit: :weeks, due_on: ~D[2026-12-02]}] =
               Puppy.list_health_entries!(actor: user)
    end

    test "editing an age entry starts on Alter; switching to Datum keeps the typed date",
         %{conn: conn, user: user} do
      saved =
        entry(user, %{kind: :vaccination, due_on: nil, due_age: 8, due_age_unit: :weeks})

      {:ok, view, _html} = live(conn, ~p"/health/#{saved.id}")

      assert has_element?(view, ~s{input[name="due_mode"][value="age"][checked]})
      assert has_element?(view, ~s{input[name="form[due_age]"][value="8"]})
      assert has_element?(view, ~s{input[name="form[due_age_unit]"][value="weeks"][checked]})

      choose_mode(view, "date")
      save(view, conn, form: %{due_on: "2026-12-05"})

      assert %{due_age: nil, due_age_unit: nil, due_on: ~D[2026-12-05]} =
               Puppy.get_health_entry!(saved.id, actor: user)
    end

    test "switching kind to Tierarzt clears the age", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/health/new")
      choose_mode(view, "age")

      view
      |> form("#health-form", form: %{due_age: "8", due_age_unit: "weeks"})
      |> render_change()

      choose_kind(view, "vet_visit")
      save(view, conn, form: %{title: "Kontrolle", due_on: "2026-12-01", due_time: "09:00"})

      assert [%{kind: :vet_visit, due_age: nil, due_age_unit: nil, due_on: ~D[2026-12-01]}] =
               Puppy.list_health_entries!(actor: user)
    end
  end

  test "without a birth date Alter is disabled with a profile link", %{conn: conn, user: user} do
    {:ok, _} = Puppy.create_profile(%{name: "Momo"}, actor: user)
    {:ok, view, _html} = live(conn, ~p"/health/new")

    assert has_element?(view, ~s{input[name="due_mode"][value="age"][disabled]})
    assert has_element?(view, ~s{a[href="/profile/edit"]}, "Geburtsdatum im Profil eintragen")
  end
end
