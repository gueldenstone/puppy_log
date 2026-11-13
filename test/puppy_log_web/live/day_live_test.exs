defmodule PuppyLogWeb.DayLiveTest do
  use PuppyLogWeb.ConnCase, async: false

  alias PuppyLog.{Clock, Daily, Puppy}

  @today ~D[2026-11-12]
  @yesterday ~D[2026-11-11]

  setup :register_and_sign_in

  setup %{user: user} do
    # routines exist before the arrival, so both days are planned
    pin_clock(Clock.local_datetime(~D[2026-11-01], ~T[06:00:00]))
    {:ok, _} = Puppy.create_profile(%{name: "Bruno", arrival_date: @yesterday}, actor: user)

    {:ok, _} =
      Daily.create_routine(%{name: "Nacht-Pipi", kind: :potty, starts_at: ~T[02:00:00]},
        actor: user
      )

    {:ok, _} =
      Daily.create_routine(%{name: "Frühstück", kind: :meal, starts_at: ~T[07:00:00]},
        actor: user
      )

    pin_clock(Clock.local_datetime(@today, ~T[08:00:00]))
    :ok
  end

  test "day view ticks off yesterday's 02:00 routine at 02:10", %{conn: conn, user: user} do
    {:ok, history, _html} = live(conn, ~p"/history")
    # yesterday both missed; today's are still open
    assert render(history) =~ "0 von 2 pünktlich"

    {:ok, view, _html} = live(conn, ~p"/history/2026-11-11")
    html = render_async(view)
    assert html =~ "Mi, 11. Nov"
    assert html =~ "Nicht erledigt"

    night = occurrence(user, @yesterday, "Nacht-Pipi")
    view |> element(~s{a[aria-label="Abhaken: Nacht-Pipi"]}) |> render_click()
    assert_patch(view, ~p"/history/2026-11-11/routine/#{night.id}")

    # the time choice starts at the planned time on that day
    assert has_element?(view, ~s{#routine-sheet-custom[value="2026-11-11T02:00"]})

    view |> form("#routine-sheet-time", %{custom: "2026-11-11T02:10"}) |> render_change()
    view |> element(~s{#routine-sheet button[phx-value-outcome="pee"]}) |> render_click()
    assert_patch(view, ~p"/history/2026-11-11")

    done = occurrence(user, @yesterday, "Nacht-Pipi")
    assert done.status == :done
    assert done.deviation_minutes == 10
    assert render_async(view) =~ "Erledigt 02:10 · Du"

    html = render(history)
    assert html =~ "50 %"
    assert html =~ "1 von 2 pünktlich"
  end

  test "skip and reopen a past routine from the row", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/history/2026-11-11")
    render_async(view)
    # planned on mount
    breakfast = occurrence(user, @yesterday, "Frühstück")

    view
    |> element(~s{button[phx-click="skip"][phx-value-id="#{breakfast.id}"]})
    |> render_click()

    assert render_async(view) =~ "Übersprungen · Du"
    assert occurrence(user, @yesterday, "Frühstück").status == :skipped

    view
    |> element(~s{button[phx-click="reopen"][phx-value-id="#{breakfast.id}"]})
    |> render_click()

    assert occurrence(user, @yesterday, "Frühstück").status == :open
  end

  test "day view deletes an event and the routine becomes missed", %{conn: conn, user: user} do
    {:ok, event} =
      Daily.log_event(
        %{kind: :meal, occurred_at: Clock.local_datetime(@yesterday, ~T[07:05:00])},
        actor: user
      )

    assert occurrence(user, @yesterday, "Frühstück").event_id == event.id

    {:ok, view, _html} = live(conn, ~p"/history/2026-11-11")
    html = render_async(view)
    assert html =~ "erfüllt Frühstück"
    assert has_element?(view, ~s{a[href="/history/2026-11-11/events/#{event.id}"]}, "Mahlzeit")

    view
    |> element(~s{button[phx-click="delete_event"][phx-value-id="#{event.id}"]})
    |> render_click()

    assert Daily.list_events_on!(@yesterday, actor: user) == []
    assert occurrence(user, @yesterday, "Frühstück").status == :open

    html = render_async(view)
    assert html =~ "Eintrag gelöscht."
    assert html =~ "An diesem Tag ist nichts eingetragen."
    refute has_element?(view, ~s{a[aria-label="Wieder öffnen: Frühstück"]})
    assert has_element?(view, ~s{a[aria-label="Abhaken: Frühstück"]})
  end

  test "back-dated event from the day view matches that day", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/history/2026-11-11")
    view |> element("a", "Eintragen") |> render_click()
    assert_patch(view, ~p"/history/2026-11-11/log")

    # starts on „Uhrzeit“ at the current time of day on that day
    assert render(view) =~ ~s{value="2026-11-11T08:00"}

    view |> element(~s{#event-form button[phx-value-kind="meal"]}) |> render_click()
    view |> form("#event-form-form", %{custom: "2026-11-11T07:05"}) |> render_change()
    assert has_element?(view, "#event-form-routine", "Erfüllt: Frühstück (07:00)")

    view |> form("#event-form-form") |> render_submit()
    assert_patch(view, ~p"/history/2026-11-11")

    assert [event] = Daily.list_events_on!(@yesterday, actor: user)
    assert occurrence(user, @yesterday, "Frühstück").event_id == event.id
    :ok = Daily.ensure_day(@today)
    assert occurrence(user, @today, "Frühstück").status == :open
    assert render_async(view) =~ "erfüllt Frühstück"
  end

  test "previous and next day, not into the future or before the arrival", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/history/2026-11-12")
    assert has_element?(view, ~s{a[href="/history/2026-11-11"][aria-label^="Vorheriger Tag"]})
    refute has_element?(view, ~s{a[aria-label^="Nächster Tag"]})

    {:ok, view, _html} = live(conn, ~p"/history/2026-11-11")
    assert has_element?(view, ~s{a[href="/history/2026-11-12"][aria-label^="Nächster Tag"]})
    refute has_element?(view, ~s{a[aria-label^="Vorheriger Tag"]})
  end

  test "invalid, future or pre-arrival dates go back to the history", %{conn: conn} do
    for {date, message} <- [
          {"2026-11-13", "Dieser Tag liegt in der Zukunft."},
          {"kein-datum", "Diesen Tag gibt es nicht."},
          {"2026-11-10", "An diesem Tag war euer Welpe noch nicht da."}
        ] do
      assert {:error, {:live_redirect, %{to: "/history", flash: flash}}} =
               live(conn, "/history/#{date}")

      assert flash["error"] == message
    end
  end

  defp occurrence(user, date, name) do
    date
    |> Daily.list_occurrences_on!(actor: user)
    |> Enum.find(&(&1.name == name))
  end
end
