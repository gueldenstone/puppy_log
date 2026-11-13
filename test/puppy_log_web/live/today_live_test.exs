defmodule PuppyLogWeb.TodayLiveTest do
  use PuppyLogWeb.ConnCase, async: false

  alias PuppyLog.{Clock, Daily, Puppy}

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

    assert has_element?(view, ~s{a[href="/settings"][aria-label*="Riv"]})
  end

  describe "routines" do
    @today ~D[2026-11-12]

    setup %{user: user} do
      pin_local(~T[06:00:00])

      {:ok, _} =
        Puppy.create_profile(%{name: "Bruno", arrival_date: ~D[2026-11-01]}, actor: user)

      meal = routine(user, %{name: "Frühstück", kind: :meal, starts_at: ~T[07:00:00]})
      potty = routine(user, %{name: "Pipi-Runde", kind: :potty, starts_at: ~T[10:00:00]})

      sleep =
        routine(user, %{
          name: "Mittagsschlaf",
          kind: :sleep,
          starts_at: ~T[12:30:00],
          ends_at: ~T[14:00:00]
        })

      :ok = Daily.ensure_day(@today)
      %{meal: meal, potty: potty, sleep: sleep}
    end

    test "shows today's routines in order with progress 0 von 3", %{conn: conn} do
      pin_local(~T[06:30:00])
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_async(view)

      assert html =~ "Routinen heute"
      assert html =~ "0 von 3"
      assert html =~ "Um 07:00"
      assert html =~ "12:30 bis 14:00"

      assert [_, after_meal] = String.split(html, "Frühstück", parts: 2)
      assert [_, after_potty] = String.split(after_meal, "Pipi-Runde", parts: 2)
      assert after_potty =~ "Mittagsschlaf"
    end

    test "tick off a meal now", %{conn: conn, user: user} do
      pin_local(~T[07:40:00])
      {:ok, view, _html} = live(conn, ~p"/")
      render_async(view)

      view |> element(~s{button[aria-label="Abhaken: Frühstück"]}) |> render_click()
      html = render_async(view)

      assert html =~ "Erledigt 07:40 · Du"
      assert html =~ "+40 Min"
      assert html =~ "1 von 3"

      [meal | _] = Daily.list_occurrences_on!(@today, actor: user)
      assert meal.status == :done
      assert meal.completed_by_id == user.id
    end

    test "potty check opens the sheet; Pipi logs an event and ticks off", %{
      conn: conn,
      user: user
    } do
      pin_local(~T[10:05:00])
      {:ok, view, _html} = live(conn, ~p"/")
      render_async(view)
      potty = occurrence(user, "Pipi-Runde")

      view |> element(~s{a[aria-label="Abhaken: Pipi-Runde"]}) |> render_click()
      assert_patch(view, ~p"/routine/#{potty.id}")
      assert has_element?(view, "#routine-sheet [role=dialog]", "Pipi-Runde")

      view |> element(~s{#routine-sheet button[phx-value-outcome="pee"]}) |> render_click()
      assert_patch(view, ~p"/")
      refute has_element?(view, "#routine-sheet")

      done = occurrence(user, "Pipi-Runde")
      assert done.status == :done
      assert done.event_id

      assert [event] = Daily.list_events_on!(@today, actor: user)
      assert %{kind: :potty, pee: true, poo: false, location: :outside} = event
      assert event.id == done.event_id
      assert render_async(view) =~ "Erledigt 10:05 · Du"
    end

    test "tick off 20 minutes ago from the sheet", %{conn: conn, user: user} do
      pin_local(~T[07:40:00])
      meal = occurrence(user, "Frühstück")
      {:ok, view, _html} = live(conn, ~p"/routine/#{meal.id}")

      view |> element(~s{#routine-sheet button[phx-value-choice="20"]}) |> render_click()
      view |> element("#routine-sheet button", "Abhaken") |> render_click()
      assert_patch(view, ~p"/")

      done = occurrence(user, "Frühstück")
      assert done.status == :done
      assert local_time(done.done_at) == ~T[07:20:00]
      assert done.deviation_minutes == 20
    end

    test "tick off at an exact time from the sheet", %{conn: conn, user: user} do
      pin_local(~T[07:40:00])
      meal = occurrence(user, "Frühstück")
      {:ok, view, _html} = live(conn, ~p"/routine/#{meal.id}")

      view |> element(~s{#routine-sheet button[phx-value-choice="custom"]}) |> render_click()

      view
      |> form("#routine-sheet-time", %{custom: "2026-11-12T07:10"})
      |> render_change()

      view |> element("#routine-sheet button", "Abhaken") |> render_click()

      assert local_time(occurrence(user, "Frühstück").done_at) == ~T[07:10:00]
    end

    test "the sheet can start on an exact time (past days)", %{user: user} do
      meal = user |> occurrence("Frühstück") |> Ash.load!([:completed_by, :assignee])

      html =
        render_component(PuppyLogWeb.RoutineSheet,
          id: "routine-sheet",
          occurrence: meal,
          current_user: user,
          return_to: "/",
          default_at: Clock.local_datetime(@today, ~T[07:00:00])
        )

      assert html =~ ~s{aria-pressed="true"}
      assert [_, pressed] = String.split(html, ~s{aria-pressed="true"}, parts: 2)
      assert pressed =~ ~r/^[^<]*>\s*Uhrzeit/
      assert html =~ ~s{value="2026-11-12T07:00"}
    end

    test "a future exact time is refused", %{conn: conn, user: user} do
      pin_local(~T[07:40:00])
      meal = occurrence(user, "Frühstück")
      {:ok, view, _html} = live(conn, ~p"/routine/#{meal.id}")

      view |> element(~s{#routine-sheet button[phx-value-choice="custom"]}) |> render_click()
      view |> form("#routine-sheet-time", %{custom: "2026-11-12T09:00"}) |> render_change()
      html = view |> element("#routine-sheet button", "Abhaken") |> render_click()

      assert html =~ "Bitte eine Uhrzeit wählen, die nicht in der Zukunft liegt."
      assert occurrence(user, "Frühstück").status == :open
    end

    test "swipe action skip", %{conn: conn, user: user} do
      pin_local(~T[07:40:00])
      meal = occurrence(user, "Frühstück")
      {:ok, view, _html} = live(conn, ~p"/")
      render_async(view)

      view
      |> element(~s{button[phx-click="skip"][phx-value-id="#{meal.id}"]}, "Überspringen")
      |> render_click()

      html = render_async(view)
      assert html =~ "Übersprungen · Du"
      assert html =~ "0 von 2"
      assert has_element?(view, ~s{button[phx-click="reopen"][phx-value-id="#{meal.id}"]})
    end

    test "a done check opens the sheet to reopen", %{conn: conn, user: user} do
      pin_local(~T[07:40:00])
      meal = occurrence(user, "Frühstück")
      {:ok, _} = Daily.complete_occurrence(meal, %{done_at: Clock.now()}, actor: user)

      {:ok, view, _html} = live(conn, ~p"/")
      render_async(view)

      view |> element(~s{a[aria-label="Wieder öffnen: Frühstück"]}) |> render_click()
      assert_patch(view, ~p"/routine/#{meal.id}")

      view |> element("#routine-sheet button", "Wieder öffnen") |> render_click()
      assert occurrence(user, "Frühstück").status == :open
      assert render_async(view) =~ "0 von 3"
    end

    test "overdue after 15 minutes", %{conn: conn} do
      pin_local(~T[10:15:00])
      {:ok, view, _html} = live(conn, ~p"/")
      html = render_async(view)
      assert html =~ "Um 10:00"
      refute html =~ "Seit 15 Min fällig"

      pin_local(~T[10:16:00])
      send(view.pid, :tick)
      html = render(view)
      assert html =~ "Seit 16 Min fällig"
      refute html =~ "Um 10:00"
      # the breakfast at 07:00 is long overdue
      assert html =~ "Seit 3 Std fällig"
    end

    test "live: the other person ticks off", %{conn: conn, user: user} do
      pin_local(~T[07:40:00])
      {:ok, view, _html} = live(conn, ~p"/")
      render_async(view)

      riv = user_fixture(%{name: "Riv"})
      meal = occurrence(user, "Frühstück")
      {:ok, _} = Daily.complete_occurrence(meal, %{done_at: Clock.now()}, actor: riv)

      html = render_async(view)
      assert html =~ "Erledigt 07:40 · Riv"
      assert html =~ "1 von 3"
    end

    test "ticking off what the other person just did shows a flash", %{conn: conn, user: user} do
      pin_local(~T[07:40:00])
      {:ok, view, _html} = live(conn, ~p"/")
      render_async(view)

      riv = user_fixture(%{name: "Riv"})
      meal = occurrence(user, "Frühstück")
      {:ok, _} = Daily.complete_occurrence(meal, %{done_at: Clock.now()}, actor: riv)

      html = view |> element(~s{button[aria-label="Abhaken: Frühstück"]}) |> render_click()
      assert html =~ "Schon erledigt"
      assert occurrence(user, "Frühstück").completed_by_id == riv.id
    end

    test "quick tiles link to the log sheet", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      for type <- ~w(pee poo meal walk) do
        assert has_element?(view, ~s{a[href="/log?type=#{type}"]})
      end

      assert has_element?(view, ~s{a[href="/log"]}, "Eintragen")
      refute has_element?(view, ~s{a[href="/weight/new"]})

      view |> element(~s{a[href="/log?type=pee"]}) |> render_click()
      assert_patch(view, ~p"/log?type=pee")
    end
  end

  test "without arrival date shows the hint", %{conn: conn, user: user} do
    {:ok, _} = Puppy.create_profile(%{name: "Bruno"}, actor: user)
    {:ok, view, _html} = live(conn, ~p"/")

    assert render(view) =~ "Tragt im Profil das Einzugsdatum ein"
    assert has_element?(view, ~s{a[href="/profile/edit"]})
  end

  test "without routines asks to set up the daily plan", %{conn: conn, user: user} do
    {:ok, _} =
      Puppy.create_profile(%{name: "Bruno", arrival_date: ~D[2026-11-01]}, actor: user)

    {:ok, view, _html} = live(conn, ~p"/")

    assert render(view) =~ "Legt euren Tagesablauf an"
    assert has_element?(view, ~s{a[href="/routines/new"]})
  end

  defp pin_local(time), do: pin_clock(Clock.local_datetime(~D[2026-11-12], time))

  defp local_time(datetime),
    do: datetime |> Clock.local() |> DateTime.to_time() |> Time.truncate(:second)

  defp routine(user, attrs) do
    {:ok, routine} = Daily.create_routine(attrs, actor: user)
    routine
  end

  defp occurrence(user, name) do
    ~D[2026-11-12]
    |> Daily.list_occurrences_on!(actor: user)
    |> Enum.find(&(&1.name == name))
  end
end
