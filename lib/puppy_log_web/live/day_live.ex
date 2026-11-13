defmodule PuppyLogWeb.DayLive do
  @moduledoc """
  One day in „Verlauf“ (`/history/:date`): its routines to tick off, skip or
  reopen afterwards (`/routine/:id`, the time choice starts at the planned
  time on past days), its events to change (`/events/:id`) or delete, and
  back-dated logging (`/log`). Days run from the arrival date to today.
  """

  use PuppyLogWeb, :live_view

  import Cinder.Refresh
  import PuppyLogWeb.RoutineRow

  alias PuppyLog.{Clock, Daily, Puppy}
  alias PuppyLog.Daily.{Event, Occurrence}
  alias PuppyLogWeb.{EventForm, RoutineActions, RoutineSheet}

  on_mount {PuppyLogWeb.LiveUserAuth, :live_user_required}

  @routines "day-routines"
  @events "day-events"
  @topics ~w(occurrences:changed events:changed routines:changed)

  @impl true
  def mount(%{"date" => param}, _session, socket) do
    today = Clock.today()
    arrival = arrival_date(socket.assigns.current_user)

    case Date.from_iso8601(param) do
      {:ok, date} ->
        cond do
          Date.after?(date, today) ->
            {:ok, leave(socket, "Dieser Tag liegt in der Zukunft.")}

          arrival && Date.before?(date, arrival) ->
            {:ok, leave(socket, "An diesem Tag war euer Welpe noch nicht da.")}

          true ->
            {:ok, setup(socket, date, today, arrival)}
        end

      {:error, _} ->
        {:ok, leave(socket, "Diesen Tag gibt es nicht.")}
    end
  end

  defp leave(socket, message),
    do: socket |> put_flash(:error, message) |> push_navigate(to: ~p"/history")

  defp setup(socket, date, today, arrival) do
    if connected?(socket), do: Enum.each(@topics, &PuppyLogWeb.Endpoint.subscribe/1)
    :ok = Daily.ensure_day(date)

    assign(socket,
      page_title: Format.short_date(date),
      date: date,
      path: ~p"/history/#{Date.to_iso8601(date)}",
      previous: if(is_nil(arrival) or Date.after?(date, arrival), do: Date.add(date, -1)),
      next: if(Date.before?(date, today), do: Date.add(date, 1)),
      now: now(),
      sheet: nil,
      event: nil,
      occurrences: Ash.Query.for_read(Occurrence, :on_date, %{date: date}),
      events: Ash.Query.for_read(Event, :on_date, %{date: date})
    )
  end

  defp arrival_date(actor) do
    case Puppy.get_profile!(actor: actor) do
      %{arrival_date: arrival} -> arrival
      nil -> nil
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :routine, %{"id" => id}) do
    case Daily.get_occurrence(id, actor: socket.assigns.current_user, load: RoutineActions.load()) do
      {:ok, occurrence} -> assign(socket, sheet: occurrence, event: nil)
      {:error, _} -> gone(socket, "Diese Routine gibt es nicht mehr.")
    end
  end

  defp apply_action(socket, :edit_event, %{"id" => id}) do
    case Daily.get_event(id, actor: socket.assigns.current_user) do
      {:ok, event} -> assign(socket, sheet: nil, event: event)
      {:error, _} -> gone(socket, "Diesen Eintrag gibt es nicht mehr.")
    end
  end

  defp apply_action(socket, _action, _params), do: assign(socket, sheet: nil, event: nil)

  defp gone(socket, message) do
    socket
    |> assign(sheet: nil, event: nil)
    |> put_flash(:error, message)
    |> push_patch(to: socket.assigns.path)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.top_bar title={Format.short_date(@date)} back={~p"/history"}>
        <:actions>
          <.day_arrow date={@previous} icon="left" label="Vorheriger Tag" />
          <.day_arrow date={@next} icon="right" label="Nächster Tag" />
        </:actions>
      </.top_bar>

      <.section_label class="pt-1">Routinen</.section_label>
      <Cinder.collection
        id="day-routines"
        query={@occurrences}
        actor={@current_user}
        layout={:list}
        search={false}
        show_filters={false}
        query_opts={[load: RoutineActions.load()]}
      >
        <:item :let={occurrence}>
          <.routine_row
            occurrence={occurrence}
            now={@now}
            current_user={@current_user}
            sheet_path={~p"/history/#{Date.to_iso8601(@date)}/routine/#{occurrence.id}"}
          />
        </:item>
        <:empty>
          <p class="py-2 text-[14px]">An diesem Tag war keine Routine geplant.</p>
        </:empty>
      </Cinder.collection>

      <.section_label class="pt-2">Einträge</.section_label>
      <Cinder.collection
        id="day-events"
        query={@events}
        actor={@current_user}
        layout={:list}
        search={false}
        show_filters={false}
        query_opts={[load: [:created_by, :occurrence]]}
      >
        <:item :let={event}>
          <.event_row event={event} current_user={@current_user} date={@date} />
        </:item>
        <:empty>
          <p class="py-2 text-[14px]">An diesem Tag ist nichts eingetragen.</p>
        </:empty>
      </Cinder.collection>

      <p class="text-center text-[12.5px] text-muted">
        Nach links wischen oder lange drücken zum Ändern, Überspringen oder Löschen.
      </p>

      <:footer>
        <.action_button patch={~p"/history/#{Date.to_iso8601(@date)}/log"}>
          <.pl_icon name="plus" class="size-5" /> Eintragen
        </.action_button>
      </:footer>
    </Layouts.app>

    <.live_component
      :if={@sheet}
      module={RoutineSheet}
      id="routine-sheet"
      occurrence={@sheet}
      current_user={@current_user}
      default_at={default_at(@sheet, @date)}
      return_to={@path}
    />

    <.live_component
      :if={@live_action == :log}
      module={EventForm}
      id="event-form"
      default_date={@date}
      current_user={@current_user}
      return_to={@path}
    />

    <.live_component
      :if={@event}
      module={EventForm}
      id="event-form"
      event={@event}
      current_user={@current_user}
      return_to={@path}
    />
    """
  end

  attr :date, :any, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp day_arrow(%{date: nil} = assigns) do
    ~H"""
    <span class="grid size-11 place-items-center text-line" aria-hidden="true">
      <.pl_icon name={@icon} />
    </span>
    """
  end

  defp day_arrow(assigns) do
    ~H"""
    <.link
      navigate={~p"/history/#{Date.to_iso8601(@date)}"}
      aria-label={"#{@label}: #{Format.short_date(@date)}"}
      class="grid size-11 place-items-center rounded-full transition hover:bg-mist active:scale-95"
    >
      <.pl_icon name={@icon} />
    </.link>
    """
  end

  attr :event, :any, required: true
  attr :current_user, :any, required: true
  attr :date, Date, required: true

  defp event_row(assigns) do
    assigns = assign(assigns, look: look(assigns.event))

    ~H"""
    <.swipe_row id={"event-#{@event.id}"}>
      <.link
        patch={~p"/history/#{Date.to_iso8601(@date)}/events/#{@event.id}"}
        class="flex min-h-14 items-center gap-3 px-4 py-2"
        aria-label={"#{@look.title} um #{hhmm(@event.occurred_at)}, ändern"}
      >
        <span class={["grid size-8 shrink-0 place-items-center rounded-full", @look.tint]}>
          <.pl_icon name={@look.icon} class="size-4" />
        </span>
        <div class="min-w-0 flex-1">
          <p class="flex items-center gap-1.5 text-[15px] leading-5">
            <span class="truncate font-medium">{@look.title}</span>
            <.chip :if={@event.location == :inside} kind={:bad} class="!py-0">Unfall</.chip>
          </p>
          <p class="truncate text-[12.5px] leading-[17px] text-muted">
            {Format.who(@event.created_by, @current_user)}<span :if={@event.occurrence}> · erfüllt {@event.occurrence.name}</span><span :if={
              @event.note
            }> · {@event.note}</span>
          </p>
        </div>
        <span class="text-[13px] tabular-nums text-muted">{hhmm(@event.occurred_at)}</span>
      </.link>
      <:actions>
        <.swipe_action
          icon="edit"
          type="button"
          phx-click={JS.patch(~p"/history/#{Date.to_iso8601(@date)}/events/#{@event.id}")}
        >
          Ändern
        </.swipe_action>
        <.swipe_action
          kind={:danger}
          icon="trash"
          type="button"
          phx-click="delete_event"
          phx-value-id={@event.id}
          data-confirm="Diesen Eintrag löschen?"
        >
          Löschen
        </.swipe_action>
      </:actions>
    </.swipe_row>
    """
  end

  @labels %{
    meal: {"Mahlzeit", "bowl"},
    walk: {"Gassi", "gassi"},
    sleep: {"Schlaf", "moon"},
    play: {"Spiel", "ball"},
    vomit: {"Erbrechen", "alert"}
  }

  defp look(%{kind: :potty, nothing: true}),
    do: %{title: "Nichts gemacht", icon: "x", tint: "bg-mist text-ink"}

  defp look(%{kind: :potty} = event) do
    what = Enum.join(Enum.filter([event.pee && "Pipi", event.poo && "Kaka"], & &1), " + ")
    where = if event.location == :inside, do: "drinnen", else: "draußen"

    {icon, tint} =
      if event.pee,
        do: {"pipi", "bg-pipi-tint text-pipi"},
        else: {"kaka", "bg-kaka-tint text-kaka"}

    %{title: "#{what} #{where}", icon: icon, tint: tint}
  end

  defp look(%{kind: :other, name: name}),
    do: %{title: name, icon: "plus", tint: "bg-mist text-ink"}

  defp look(%{kind: kind}) do
    {title, icon} = Map.fetch!(@labels, kind)
    %{title: title, icon: icon, tint: "bg-mist text-ink"}
  end

  # Past days start the time choice at the planned time on that day.
  defp default_at(occurrence, date) do
    if date != Clock.today(), do: Clock.local_datetime(date, occurrence.planned_start)
  end

  @impl true
  def handle_event(event, %{"id" => id}, socket) when event in ~w(complete skip reopen) do
    case RoutineActions.run(event, id, socket.assigns.current_user) do
      {:ok, updated} ->
        {:noreply, update_item(socket, @routines, updated.id, fn _ -> updated end)}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("delete_event", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    with {:ok, event} <- Daily.get_event(id, actor: actor),
         :ok <- Daily.delete_event(event, actor: actor) do
      {:noreply, put_flash(socket, :info, "Eintrag gelöscht.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Löschen hat nicht geklappt.")}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{}, socket) do
    {:noreply,
     socket
     |> assign(now: now())
     |> refresh_sheet()
     |> refresh_table(@routines, silent: true)
     |> refresh_table(@events, silent: true)}
  end

  defp refresh_sheet(%{assigns: %{sheet: %Occurrence{id: id}}} = socket) do
    case Daily.get_occurrence(id, actor: socket.assigns.current_user, load: RoutineActions.load()) do
      {:ok, occurrence} -> assign(socket, sheet: occurrence)
      {:error, _} -> socket |> assign(sheet: nil) |> push_patch(to: socket.assigns.path)
    end
  end

  defp refresh_sheet(socket), do: socket

  defp hhmm(datetime), do: datetime |> Clock.local() |> Calendar.strftime("%H:%M")
  defp now, do: Clock.now() |> DateTime.to_naive()
end
