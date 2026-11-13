defmodule PuppyLogWeb.RoutinesLive do
  @moduledoc """
  The household's routines („Routinen“, entwuerfe/06): all active routines by
  time with schedule, assignee and reminder. Works before the puppy's arrival
  so the daily plan can be prepared.
  """

  use PuppyLogWeb, :live_view

  import Cinder.Refresh

  alias PuppyLog.Daily.Routine
  alias PuppyLog.Puppy
  alias PuppyLogWeb.RoutineFormLive

  on_mount {PuppyLogWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket) do
      PuppyLogWeb.Endpoint.subscribe("routines:changed")
      PuppyLogWeb.Endpoint.subscribe("users:changed")
      PuppyLogWeb.Endpoint.subscribe("puppy_profile:changed")
    end

    # Reached from „Verlauf“ (default) or from the settings.
    back = if params["from"] == "settings", do: ~p"/settings", else: ~p"/history"

    {:ok, socket |> assign(page_title: "Routinen", back: back) |> assign_puppy_name()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.top_bar title="Routinen" back={@back} />
      <p class="-mt-1 px-1 text-[14px] leading-5 text-muted">
        Wiederkehrende Aufgaben für {@puppy_name}. Sie erscheinen auf „Heute“ und erinnern euch.
      </p>

      <Cinder.collection
        id="routines"
        query={Ash.Query.for_read(Routine, :active)}
        actor={@current_user}
        layout={:list}
        search={false}
        show_filters={false}
        query_opts={[load: [:assignee]]}
      >
        <:item :let={routine}>
          <.link
            navigate={~p"/routines/#{routine.id}"}
            id={"routine-#{routine.id}"}
            class="flex min-h-16 items-center gap-3 px-4 py-2.5 transition hover:bg-canvas active:bg-mist"
          >
            <span class={[
              "grid size-9 shrink-0 place-items-center rounded-full",
              if(routine.kind == :potty, do: "bg-pipi-tint text-pipi", else: "bg-mist text-ink")
            ]}>
              <.pl_icon name={RoutineFormLive.kind_icon(routine.kind)} class="size-[18px]" />
            </span>
            <div class="min-w-0 flex-1">
              <p class="truncate text-[15px] leading-5 font-medium">{routine.name}</p>
              <p class="truncate text-[12.5px] leading-[17px] text-muted tabular-nums">
                {schedule(routine)}<span :if={routine.assignee}> · {Format.who(
                  routine.assignee,
                  @current_user
                )}</span>
              </p>
            </div>
            <.pl_icon
              :if={routine.remind?}
              name="bell"
              class="size-4 shrink-0 text-muted"
              aria-label="Erinnert"
            />
            <span :if={!routine.remind?} class="text-[12.5px] text-muted">aus</span>
            <.pl_icon name="right" class="size-[18px] shrink-0 text-muted/70" />
          </.link>
        </:item>
        <:empty>
          <div class="flex flex-col items-center gap-2 py-2">
            <span class="grid size-12 place-items-center rounded-full bg-mist text-muted">
              <.pl_icon name="clock" />
            </span>
            <p class="font-semibold text-ink">Noch keine Routine</p>
            <p class="text-[14px]">
              Fütterung, Pipi-Runden, Schlaf: einmal festlegen, dann steht alles jeden Tag auf „Heute“.
            </p>
          </div>
        </:empty>
      </Cinder.collection>

      <:footer>
        <.action_button navigate={~p"/routines/new"}>
          <.pl_icon name="plus" class="size-5" /> Neue Routine
        </.action_button>
      </:footer>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "puppy_profile:changed"}, socket) do
    {:noreply, assign_puppy_name(socket)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{}, socket) do
    {:noreply, refresh_table(socket, "routines", silent: true)}
  end

  defp assign_puppy_name(socket) do
    name =
      case Puppy.get_profile!(actor: socket.assigns.current_user) do
        %{name: name} -> name
        nil -> "euren Welpen"
      end

    assign(socket, puppy_name: name)
  end

  defp schedule(%{starts_at: starts_at, ends_at: nil, weekdays: weekdays}),
    do: "#{hhmm(starts_at)} · #{Format.weekdays(weekdays)}"

  defp schedule(%{starts_at: starts_at, ends_at: ends_at, weekdays: weekdays}),
    do: "#{hhmm(starts_at)} bis #{hhmm(ends_at)} · #{Format.weekdays(weekdays)}"

  defp hhmm(time), do: Calendar.strftime(time, "%H:%M")
end
