defmodule PuppyLogWeb.EventFormTest do
  use PuppyLogWeb.ConnCase, async: false

  alias PuppyLog.{Clock, Daily, Puppy}
  alias PuppyLogWeb.EventForm

  @today ~D[2026-11-12]

  setup :register_and_sign_in

  setup %{user: user} do
    pin_local(~T[06:00:00])

    {:ok, _} = Puppy.create_profile(%{name: "Bruno", arrival_date: ~D[2026-11-01]}, actor: user)

    routine(user, %{name: "Pipi-Runde", kind: :potty, starts_at: ~T[10:00:00]})
    routine(user, %{name: "Mittags-Pipi", kind: :potty, starts_at: ~T[12:00:00]})
    :ok = Daily.ensure_day(@today)
    :ok
  end

  test "Pipi quick button preselects pee outside and shows the auto match", %{conn: conn} do
    pin_local(~T[10:05:00])
    {:ok, view, _html} = live(conn, ~p"/log?type=pee")

    assert has_element?(view, ~s{#event-form button[aria-pressed="true"]}, "Lösen")
    assert has_element?(view, ~s{#event-form button[aria-pressed="true"]}, "Pipi")
    assert has_element?(view, ~s{#event-form button[aria-pressed="true"]}, "Draußen")
    assert has_element?(view, ~s{#event-form button[aria-pressed="false"]}, "Kaka")
    assert has_element?(view, "#event-form-routine", "Erfüllt: Pipi-Runde (10:00)")
    assert render(view) =~ "Zählt für die Stubenreinheit."
  end

  test "adding Kaka to the same entry", %{conn: conn, user: user} do
    pin_local(~T[10:05:00])
    {:ok, view, _html} = live(conn, ~p"/log?type=pee")

    view |> element(~s{#event-form button[phx-value-field="poo"]}) |> render_click()
    view |> form("#event-form-form") |> render_submit()
    assert_patch(view, ~p"/")
    assert render(view) =~ "Eingetragen."

    assert [event] = Daily.list_events_on!(@today, actor: user)
    assert %{kind: :potty, pee: true, poo: true, location: :outside} = event
    assert occurrence(user, "Pipi-Runde").event_id == event.id
  end

  test "inside shows the accident hint and no routine area", %{conn: conn, user: user} do
    pin_local(~T[10:05:00])
    {:ok, view, _html} = live(conn, ~p"/log?type=pee")

    view |> element(~s{#event-form button[phx-value-location="inside"]}) |> render_click()

    assert render(view) =~ "Wird als Unfall gezählt und erfüllt keine Routine."
    refute has_element?(view, "#event-form-routine")

    view |> form("#event-form-form") |> render_submit()
    assert [%{location: :inside}] = Daily.list_events_on!(@today, actor: user)
    assert occurrence(user, "Pipi-Runde").status == :open
  end

  test "Nichts gemacht clears pee and poo and disables Drinnen", %{conn: conn} do
    pin_local(~T[10:05:00])
    {:ok, view, _html} = live(conn, ~p"/log?type=pee")

    view |> element(~s{#event-form button[phx-value-field="nothing"]}) |> render_click()

    assert has_element?(
             view,
             ~s{#event-form button[phx-value-field="nothing"][aria-pressed="true"]}
           )

    assert has_element?(view, ~s{#event-form button[phx-value-field="pee"][aria-pressed="false"]})
    assert has_element?(view, ~s{#event-form button[phx-value-location="inside"][disabled]})
  end

  test "outside tolerance offers a choice", %{conn: conn, user: user} do
    pin_local(~T[10:40:00])
    {:ok, view, _html} = live(conn, ~p"/log?type=pee")
    first = occurrence(user, "Pipi-Runde")
    second = occurrence(user, "Mittags-Pipi")

    refute render(view) =~ "Erfüllt:"
    assert has_element?(view, ~s{#event-form-routine input[type=radio][value="#{first.id}"]})
    assert has_element?(view, ~s{#event-form-routine input[type=radio][value="#{second.id}"]})
    assert has_element?(view, ~s{#event-form-routine input[type=radio][value="none"]})
    refute has_element?(view, "#event-form-routine input[checked]")

    # closest first
    html = view |> element("#event-form-routine") |> render()
    assert [_, rest] = String.split(html, "Pipi-Runde", parts: 2)
    assert rest =~ "Mittags-Pipi"

    view |> form("#event-form-form", %{routine: first.id}) |> render_change()
    view |> form("#event-form-form") |> render_submit()
    assert_patch(view, ~p"/")

    [event] = Daily.list_events_on!(@today, actor: user)
    assert %{status: :done, event_id: event_id} = occurrence(user, "Pipi-Runde")
    assert event_id == event.id
    assert occurrence(user, "Mittags-Pipi").status == :open
  end

  test "ändern reveals the choice list and keine leaves the routine open", %{
    conn: conn,
    user: user
  } do
    pin_local(~T[10:05:00])
    {:ok, view, _html} = live(conn, ~p"/log?type=pee")
    first = occurrence(user, "Pipi-Runde")

    view |> element("#event-form-routine button", "ändern") |> render_click()
    assert has_element?(view, ~s{#event-form-routine input[value="#{first.id}"][checked]})

    view |> form("#event-form-form", %{routine: "none"}) |> render_change()
    view |> form("#event-form-form") |> render_submit()

    assert [_event] = Daily.list_events_on!(@today, actor: user)
    assert occurrence(user, "Pipi-Runde").status == :open
  end

  test "the routine area follows the time choice", %{conn: conn} do
    pin_local(~T[10:20:00])
    {:ok, view, _html} = live(conn, ~p"/log?type=pee")
    refute render(view) =~ "Erfüllt:"

    view |> element(~s{#event-form button[phx-value-choice="15"]}) |> render_click()
    assert has_element?(view, "#event-form-routine", "Erfüllt: Pipi-Runde (10:00)")
  end

  test "Anderes requires a name and offers recent names", %{conn: conn, user: user} do
    pin_local(~T[09:00:00])
    {:ok, _} = Daily.log_event(%{kind: :other, name: "Krallen geschnitten"}, actor: user)
    {:ok, view, _html} = live(conn, ~p"/log")

    view |> element(~s{#event-form button[phx-value-kind="other"]}) |> render_click()
    assert render(view) =~ "Was genau?"

    html = view |> form("#event-form-form", %{name: ""}) |> render_submit()
    assert html =~ "ist erforderlich"
    assert length(Daily.list_events_on!(@today, actor: user)) == 1

    view |> element("#event-form button", "Krallen geschnitten") |> render_click()
    view |> form("#event-form-form") |> render_submit()
    assert_patch(view, ~p"/")

    assert [%{kind: :other, name: "Krallen geschnitten"}, _] =
             Daily.list_events_on!(@today, actor: user)
  end

  test "vor 20 Min stores 20 minutes earlier", %{conn: conn, user: user} do
    pin_local(~T[10:05:00])
    {:ok, view, _html} = live(conn, ~p"/log?type=meal")

    view |> element(~s{#event-form button[phx-value-choice="20"]}) |> render_click()
    view |> form("#event-form-form", %{note: "Halbe Portion"}) |> render_submit()

    assert [event] = Daily.list_events_on!(@today, actor: user)
    assert %{kind: :meal, note: "Halbe Portion"} = event
    assert local_time(event.occurred_at) == ~T[09:45:00]
  end

  test "unknown type is ignored", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/log?type=nonsense")

    assert has_element?(view, "#event-form [role=dialog]", "Ereignis eintragen")
    refute has_element?(view, ~s{#event-form button[phx-value-kind][aria-pressed="true"]})
  end

  test "Uhrzeit rejects a time in the future", %{conn: conn, user: user} do
    pin_local(~T[10:05:00])
    {:ok, view, _html} = live(conn, ~p"/log?type=walk")

    view |> element(~s{#event-form button[phx-value-choice="custom"]}) |> render_click()
    html = view |> form("#event-form-form", %{custom: "2026-11-12T11:00"}) |> render_submit()

    assert html =~ "nicht in der Zukunft"
    assert Daily.list_events_on!(@today, actor: user) == []
  end

  test "a past default_date starts on Uhrzeit at the current time of day", %{user: user} do
    pin_local(~T[10:05:00])

    html =
      render_component(EventForm,
        id: "event-form",
        current_user: user,
        default_date: ~D[2026-11-11],
        return_to: "/"
      )

    assert html =~ ~s{value="2026-11-11T10:05"}
    assert html =~ ~r/phx-value-choice="custom"[^>]*aria-pressed="true"/

    html =
      render_component(EventForm,
        id: "event-form",
        current_user: user,
        default_date: @today,
        return_to: "/"
      )

    assert html =~ ~r/phx-value-choice="now"[^>]*aria-pressed="true"/
  end

  test "Nichts gemacht after Drinnen brings the routine area back", %{conn: conn} do
    pin_local(~T[10:05:00])
    {:ok, view, _html} = live(conn, ~p"/log?type=pee")

    view |> element(~s{#event-form button[phx-value-location="inside"]}) |> render_click()
    refute has_element?(view, "#event-form-routine")

    view |> element(~s{#event-form button[phx-value-field="nothing"]}) |> render_click()
    assert has_element?(view, "#event-form-routine", "Erfüllt: Pipi-Runde (10:00)")
  end

  describe "editing" do
    defmodule Host do
      use PuppyLogWeb, :live_view

      def mount(_params, %{"event_id" => id, "user" => user}, socket) do
        {:ok, event} = PuppyLog.Daily.get_event(id, actor: user)
        {:ok, assign(socket, event: event, user: user, rev: 0)}
      end

      # re-renders the component with a freshly read (unloaded) event;
      # `rev` changes so the component is updated
      def handle_info(:reload, socket) do
        {:ok, event} =
          PuppyLog.Daily.get_event(socket.assigns.event.id, actor: socket.assigns.user)

        {:noreply, socket |> assign(event: event) |> update(:rev, &(&1 + 1))}
      end

      def render(assigns) do
        ~H"""
        <.live_component
          module={PuppyLogWeb.EventForm}
          id="event-form"
          event={@event}
          rev={@rev}
          current_user={@user}
          return_to="/"
        />
        """
      end
    end

    test "keeps an explicit link when only the note changes", %{conn: conn, user: user} do
      pin_local(~T[10:40:00])
      second = occurrence(user, "Mittags-Pipi")

      {:ok, event} =
        Daily.log_event(
          %{kind: :potty, pee: true, location: :outside, routine: second.id},
          actor: user
        )

      {:ok, view, _html} = live(conn, ~p"/history/2026-11-12/events/#{event.id}")

      assert has_element?(view, "#event-form [role=dialog]", "Eintrag bearbeiten")
      assert has_element?(view, ~s{#event-form-routine input[value="#{second.id}"][checked]})

      view |> form("#event-form-form", %{note: "Lange gebraucht"}) |> render_submit()
      assert_patch(view, ~p"/history/2026-11-12")
      refute has_element?(view, "#event-form")

      assert [%{note: "Lange gebraucht"} = updated] = Daily.list_events_on!(@today, actor: user)
      assert local_time(updated.occurred_at) == local_time(event.occurred_at)
      assert occurrence(user, "Mittags-Pipi").event_id == event.id
      assert occurrence(user, "Pipi-Runde").status == :open
    end

    @tag :capture_log
    test "keeps a link to another day's occurrence across parent re-renders", %{
      conn: conn,
      user: user
    } do
      pin_local(~T[10:05:00])
      yesterday_potty = occurrence(user, "Pipi-Runde")

      pin_clock(Clock.local_datetime(~D[2026-11-13], ~T[09:00:00]))

      {:ok, event} =
        Daily.log_event(
          %{kind: :potty, pee: true, location: :outside, routine: yesterday_potty.id},
          actor: user
        )

      {:ok, view, _html} =
        live_isolated(conn, Host, session: %{"event_id" => event.id, "user" => user})

      send(view.pid, :reload)
      # wait until the host handled it, then let the client see the new diff
      :sys.get_state(view.pid)
      render(view)

      assert has_element?(
               view,
               ~s{#event-form-routine input[value="#{yesterday_potty.id}"][checked]}
             )

      Process.flag(:trap_exit, true)
      catch_exit(view |> form("#event-form-form", %{note: "Gestern verlinkt"}) |> render_submit())

      assert %{note: "Gestern verlinkt"} = Daily.get_event!(event.id, actor: user)
      assert occurrence(user, "Pipi-Runde").event_id == event.id
    end
  end

  defp pin_local(time), do: pin_clock(Clock.local_datetime(@today, time))

  defp local_time(datetime),
    do: datetime |> Clock.local() |> DateTime.to_time() |> Time.truncate(:second)

  defp routine(user, attrs) do
    {:ok, routine} = Daily.create_routine(attrs, actor: user)
    routine
  end

  defp occurrence(user, name) do
    @today
    |> Daily.list_occurrences_on!(actor: user)
    |> Enum.find(&(&1.name == name))
  end
end
