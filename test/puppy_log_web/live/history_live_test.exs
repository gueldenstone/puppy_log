defmodule PuppyLogWeb.HistoryLiveTest do
  use PuppyLogWeb.ConnCase, async: false

  alias PuppyLog.{Clock, Daily, Puppy}
  alias PuppyLog.Daily.Occurrence

  @today ~D[2026-11-12]

  setup :register_and_sign_in

  describe "with an arrival date" do
    setup %{user: user} do
      pin_clock(Clock.local_datetime(@today, ~T[20:00:00]))

      {:ok, _} =
        Puppy.create_profile(%{name: "Bruno", arrival_date: ~D[2026-08-01]}, actor: user)

      :ok
    end

    test "default period one week shows rate and per-routine stats", %{conn: conn, user: user} do
      breakfast = routine(user, "Frühstück")
      occ(breakfast, ~D[2026-11-08], :done, 5)
      occ(breakfast, ~D[2026-11-09], :done, 25)
      occ(breakfast, ~D[2026-11-10], :done, 19)
      occ(breakfast, ~D[2026-11-11], :skipped)
      # outside the week
      occ(breakfast, ~D[2026-11-01], :done, 0)

      {:ok, view, html} = live(conn, ~p"/history")

      assert html =~ "Verlauf"
      assert has_element?(view, ~s{nav[aria-label="Zeitraum"] a[aria-current="page"]}, "1 Woche")
      assert html =~ "6. Nov bis 12. Nov"
      assert html =~ "33 %"
      assert html =~ "1 von 3 pünktlich"

      assert has_element?(view, ~s{a[href="/history/2026-11-09"] svg[role="img"]})

      assert has_element?(
               view,
               ~s{svg[role="img"][aria-label="So, 8. Nov: 100 Prozent eingehalten, 1 von 1"]}
             )

      assert html =~ "eingehalten 1 von 3"
      # (5 + 25 + 19) / 3 = 16.3
      assert html =~ "Ø 16 Min zu spät"
      assert html =~ "1× übersprungen"
      assert has_element?(view, ~s{a[href="/history/2026-11-12"]}, "Heute ansehen")
    end

    test "deviation wording" do
      assert PuppyLogWeb.HistoryLive.deviation(12) == "Ø 12 Min zu spät"
      assert PuppyLogWeb.HistoryLive.deviation(-3) == "Ø 3 Min zu früh"
      assert PuppyLogWeb.HistoryLive.deviation(0) == "pünktlich"
      assert PuppyLogWeb.HistoryLive.deviation(nil) == nil
    end

    test "switching to 2 Monate shows weekly buckets", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history")

      view |> element(~s{nav[aria-label="Zeitraum"] a}, "2 Monate") |> render_click()
      assert_patch(view, ~p"/history?period=2m")

      html = render(view)
      assert html =~ "KW 46"
      assert has_element?(view, ~s{nav[aria-label="Zeitraum"] a[aria-current="page"]}, "2 Monate")
      # weekly bars are no links into a day
      refute has_element?(view, ~s{a[href="/history/2026-11-12"] svg[role="img"]})
    end

    test "an unknown period falls back to one week", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/history?period=nonsense")
      assert has_element?(view, ~s{nav[aria-label="Zeitraum"] a[aria-current="page"]}, "1 Woche")
    end

    test "accident card with previous comparison", %{conn: conn, user: user} do
      for day <- 1..3, do: potty(user, Date.add(@today, -day), %{pee: true, location: :inside})
      potty(user, ~D[2026-11-10], %{pee: true, poo: true, location: :outside})
      potty(user, ~D[2026-11-10], %{nothing: true, location: :outside})

      for day <- 8..13, do: potty(user, Date.add(@today, -day), %{poo: true, location: :inside})

      {:ok, view, html} = live(conn, ~p"/history")

      assert has_element?(view, "p", "3")
      assert html =~ "Unfälle drinnen"
      assert html =~ "Vorher: 6"
      assert html =~ "1 draußen · 3 drinnen"
      assert html =~ "1 draußen · 0 drinnen"
      assert html =~ "Nichts gemacht: 1"
      assert has_element?(view, ~s{svg[role="img"][aria-label="Pipi: 25 Prozent draußen"]})
    end

    test "no comparison when the previous period lies before the arrival", %{
      conn: conn,
      user: user
    } do
      {:ok, _} =
        Puppy.update_profile(Puppy.get_profile!(actor: user), %{arrival_date: ~D[2026-11-10]},
          actor: user
        )

      {:ok, _view, html} = live(conn, ~p"/history")
      refute html =~ "Vorher"
    end
  end

  test "no arrival date shows the profile hint", %{conn: conn, user: user} do
    {:ok, _} = Puppy.create_profile(%{name: "Bruno"}, actor: user)
    {:ok, view, html} = live(conn, ~p"/history")

    assert html =~ "Tragt im Profil das Einzugsdatum ein"
    assert has_element?(view, ~s{a[href="/profile/edit"]})
    refute html =~ "Routinen eingehalten"

    assert has_element?(
             view,
             ~s{nav[aria-label="Hauptnavigation"] a[aria-current="page"]},
             "Verlauf"
           )
  end

  # Created today after its start time, so the planner never plans it.
  defp routine(user, name) do
    {:ok, routine} =
      Daily.create_routine(%{name: name, kind: :meal, starts_at: ~T[07:00:00]}, actor: user)

    routine
  end

  defp occ(routine, date, status, deviation \\ nil) do
    Ash.Seed.seed!(Occurrence, %{
      routine_id: routine.id,
      date: date,
      name: routine.name,
      kind: routine.kind,
      planned_start: routine.starts_at,
      status: status,
      deviation_minutes: deviation
    })
  end

  defp potty(user, date, attrs) do
    {:ok, event} =
      Daily.log_event(
        Map.merge(
          %{kind: :potty, occurred_at: Clock.local_datetime(date, ~T[10:00:00]), routine: "none"},
          attrs
        ),
        actor: user
      )

    event
  end
end
