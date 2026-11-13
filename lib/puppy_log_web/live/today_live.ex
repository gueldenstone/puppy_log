defmodule PuppyLogWeb.TodayLive do
  @moduledoc """
  Start screen „Heute“ (docs/design/Main.dc.html, entwuerfe/01): today's
  routines to tick off, the tick-off sheet (`/routine/:id`) and the quick
  log buttons with the log sheet (`/log`, `type` presets the kind, see
  `PuppyLogWeb.EventForm.preset/1`).
  """

  use PuppyLogWeb, :live_view

  import Cinder.Refresh
  import PuppyLogWeb.RoutineRow

  alias PuppyLog.{Accounts, Clock, Daily, Puppy}
  alias PuppyLog.Daily.Occurrence
  alias PuppyLog.Puppy.{Age, Weight}
  alias PuppyLogWeb.{EventForm, RoutineSheet}

  on_mount {PuppyLogWeb.LiveUserAuth, :live_user_required}

  @collection "routines-today"
  @load [:completed_by, :assignee]
  @tick_ms 60_000

  @quick [
    {"pee", "Pipi", "pipi", "text-pipi", "bg-pipi-tint"},
    {"poo", "Kaka", "kaka", "text-kaka", "bg-kaka-tint"},
    {"meal", "Mahlzeit", "bowl", "text-ink", "bg-mist"},
    {"walk", "Gassi", "gassi", "text-ink", "bg-mist"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      for topic <-
            ~w(puppy_profile:changed weight_entries:changed occurrences:changed events:changed routines:changed),
          do: PuppyLogWeb.Endpoint.subscribe(topic)

      :timer.send_interval(@tick_ms, :tick)
    end

    {:ok,
     socket
     |> assign(page_title: "Heute", sheet: nil, log_preset: %{}, today: nil, quick: @quick)
     |> load()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :routine, %{"id" => id}) do
    case Daily.get_occurrence(id, actor: socket.assigns.current_user, load: @load) do
      {:ok, occurrence} ->
        assign(socket, sheet: occurrence)

      {:error, _} ->
        socket
        |> put_flash(:error, "Diese Routine gibt es nicht mehr.")
        |> push_patch(to: ~p"/")
    end
  end

  defp apply_action(socket, :log, params),
    do: assign(socket, sheet: nil, log_preset: EventForm.preset(params["type"]))

  defp apply_action(socket, _action, _params), do: assign(socket, sheet: nil)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} tab={:today}>
      <header class="flex items-center gap-3 px-1">
        <.link
          navigate={if @profile, do: ~p"/profile", else: ~p"/profile/edit"}
          class="flex min-w-0 flex-1 items-center gap-3 rounded-2xl transition active:opacity-70"
          aria-label={
            if @profile, do: "Profil von #{@profile.name} öffnen", else: "Welpenprofil anlegen"
          }
        >
          <.puppy_photo profile={@profile} />
          <div class="min-w-0">
            <h1 class="truncate font-display text-[26px] leading-[30px] font-semibold">
              {if @profile, do: @profile.name, else: "Puppy Log"}
            </h1>
            <p class="truncate text-[14px] leading-5 text-muted">{@subtitle}</p>
          </div>
        </.link>
        <.link
          navigate={~p"/settings"}
          class="flex rounded-full transition active:opacity-70"
          aria-label={"Haushalt und Mitteilungen: " <> Enum.map_join(@household, ", ", &Format.user_name/1)}
        >
          <.avatar
            :for={{user, index} <- Enum.with_index(@household)}
            user={user}
            current_user={@current_user}
            class={index > 0 && "-ml-2"}
          />
        </.link>
      </header>

      <.card :if={!@profile} class="flex flex-col gap-3">
        <div class="flex items-center gap-3">
          <span class="grid size-11 shrink-0 place-items-center rounded-full bg-accent-tint text-accent">
            <.pl_icon name="paw" />
          </span>
          <div>
            <p class="font-semibold">Willkommen!</p>
            <p class="text-[14px] text-muted">Legt zuerst das Profil eures Welpen an.</p>
          </div>
        </div>
        <.action_button navigate={~p"/profile/edit"}>Welpenprofil anlegen</.action_button>
      </.card>

      <%= case @plan do %>
        <% :no_arrival -> %>
          <.empty_state icon="clock" title="Wann zieht euer Welpe ein?">
            Tragt im Profil das Einzugsdatum ein, dann stehen hier ab diesem Tag eure Routinen zum Abhaken.
            <:action>
              <.action_button variant={:secondary} navigate={~p"/profile/edit"}>
                Einzugsdatum eintragen
              </.action_button>
              <.prepare_routines_link />
            </:action>
          </.empty_state>
        <% {:before_arrival, date} -> %>
          <.empty_state icon="clock" title="Bald geht es los">
            Ab dem Einzug am {Format.long_date(date)} stehen hier eure Routinen zum Abhaken.
            <:action>
              <.prepare_routines_link />
            </:action>
          </.empty_state>
        <% :no_routines -> %>
          <.empty_state icon="clock" title="Legt euren Tagesablauf an">
            Fütterung, Pipi-Runden, Schlaf: einmal festlegen, dann hakt ihr hier jeden Tag ab und bekommt Erinnerungen auf beide Handys.
            <:action>
              <.action_button navigate={~p"/routines/new"}>
                <.pl_icon name="plus" class="size-5" /> Erste Routine anlegen
              </.action_button>
            </:action>
          </.empty_state>
        <% :nothing_today -> %>
          <.empty_state icon="sparkle" title="Heute steht nichts an">
            Für heute ist keine Routine geplant.
          </.empty_state>
        <% :routines -> %>
          <.progress_card occurrences={@occurrences} />

          <Cinder.collection
            id="routines-today"
            query={@query}
            actor={@current_user}
            layout={:list}
            search={false}
            show_filters={false}
            query_opts={[load: [:completed_by, :assignee]]}
          >
            <:item :let={occurrence}>
              <.routine_row
                occurrence={occurrence}
                now={@now}
                current_user={@current_user}
                sheet_path={~p"/routine/#{occurrence.id}"}
              />
            </:item>
          </Cinder.collection>

          <p class="text-center text-[12.5px] text-muted">
            Nach links wischen: überspringen · Antippen: Details
          </p>
        <% nil -> %>
      <% end %>

      <section class="flex flex-col gap-2 pt-1">
        <.section_label>Schnell eintragen</.section_label>
        <div class="grid grid-cols-4 gap-2">
          <.link
            :for={{type, label, icon, color, tint} <- @quick}
            patch={~p"/log?type=#{type}"}
            class={[
              "flex min-h-[84px] flex-col items-center justify-center gap-1.5 rounded-[14px] border border-line bg-card text-[13px] font-semibold",
              "transition hover:-translate-y-px hover:shadow-[0_2px_8px_rgba(20,32,27,0.08)] active:scale-95",
              color
            ]}
          >
            <span class={["grid size-9 place-items-center rounded-full", tint]}>
              <.pl_icon name={icon} class="size-5" />
            </span>
            {label}
          </.link>
        </div>
        <.action_button variant={:secondary} patch={~p"/log"}>
          <.pl_icon name="plus" class="size-5" /> Eintragen
        </.action_button>
      </section>
    </Layouts.app>

    <.live_component
      :if={@sheet}
      module={RoutineSheet}
      id="routine-sheet"
      occurrence={@sheet}
      current_user={@current_user}
      return_to={~p"/"}
    />

    <.live_component
      :if={@live_action == :log}
      module={EventForm}
      id="event-form"
      preset={@log_preset}
      current_user={@current_user}
      return_to={~p"/"}
    />
    """
  end

  # Routines can be set up before the puppy moves in.
  defp prepare_routines_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/routines"}
      class="mt-1 flex min-h-11 items-center justify-center gap-1 rounded-xl text-[15px] font-semibold text-accent transition hover:bg-accent-tint active:scale-[0.98]"
    >
      Tagesablauf vorbereiten <.pl_icon name="right" class="size-4" />
    </.link>
    """
  end

  attr :occurrences, :list, required: true

  defp progress_card(assigns) do
    skipped = Enum.count(assigns.occurrences, &(&1.status == :skipped))
    total = length(assigns.occurrences) - skipped
    done = Enum.count(assigns.occurrences, &(&1.status == :done))
    percent = if total > 0, do: round(done * 100 / total), else: 0

    assigns = assign(assigns, skipped: skipped, total: total, done: done, percent: percent)

    ~H"""
    <.card>
      <div class="flex items-baseline justify-between">
        <span class="text-[13px] leading-[18px] font-medium text-muted">Routinen heute</span>
        <span class="text-[13px] leading-[18px] tabular-nums text-muted">{@percent} %</span>
      </div>
      <p class="mt-0.5 font-display text-[28px] leading-[34px] font-semibold tabular-nums">
        {@done} von {@total}
      </p>
      <.progress value={@percent} label={"#{@done} von #{@total} Routinen erledigt"} class="mt-2.5" />
      <p :if={@skipped > 0} class="mt-2 text-[12.5px] text-muted">
        {if @skipped == 1, do: "1 übersprungen zählt", else: "#{@skipped} übersprungen zählen"} nicht mit
      </p>
    </.card>
    """
  end

  @impl true
  def handle_event("complete", %{"id" => id}, socket) do
    mutate(socket, id, &Daily.complete_occurrence(&1, %{done_at: Clock.utc_now()}, &2))
  end

  def handle_event("skip", %{"id" => id}, socket),
    do: mutate(socket, id, &Daily.skip_occurrence/2)

  def handle_event("reopen", %{"id" => id}, socket),
    do: mutate(socket, id, &Daily.reopen_occurrence/2)

  # Shows the result right away; the PubSub broadcast refreshes the rest.
  defp mutate(socket, id, action) do
    opts = [actor: socket.assigns.current_user]

    with {:ok, occurrence} <- Daily.get_occurrence(id, opts),
         {:ok, updated} <- action.(occurrence, opts) do
      updated = Ash.load!(updated, @load, opts)

      {:noreply,
       socket
       |> update_item(@collection, updated.id, fn _ -> updated end)
       |> load()}
    else
      {:error, error} ->
        {:noreply, put_flash(socket, :error, RoutineSheet.error_message(error))}
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    if Clock.today() == socket.assigns.today,
      do: {:noreply, assign(socket, now: now())},
      else: {:noreply, load(socket)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{topic: topic}, socket)
      when topic in ["occurrences:changed", "events:changed", "routines:changed"] do
    {:noreply, socket |> load() |> refresh_sheet() |> refresh_table(@collection, silent: true)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{}, socket), do: {:noreply, load(socket)}

  defp refresh_sheet(%{assigns: %{sheet: %Occurrence{id: id}}} = socket) do
    case Daily.get_occurrence(id, actor: socket.assigns.current_user, load: @load) do
      {:ok, occurrence} -> assign(socket, sheet: occurrence)
      {:error, _} -> socket |> assign(sheet: nil) |> push_patch(to: ~p"/")
    end
  end

  defp refresh_sheet(socket), do: socket

  defp load(socket) do
    actor = socket.assigns.current_user
    profile = Puppy.get_profile!(actor: actor)
    summary = Puppy.weight_summary(actor: actor)
    today = Clock.today()

    subtitle =
      [
        profile && Age.describe(profile.birth_date, today),
        summary.latest && "#{Weight.to_kg_string(summary.latest.weight_grams)} kg",
        Format.short_date(today)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

    household =
      Accounts.list_users!(actor: actor)
      |> Enum.sort_by(&(&1.id != actor.id))

    {plan, occurrences} = plan(profile, today, actor)

    socket
    |> assign(profile: profile, subtitle: subtitle, household: household, now: now())
    |> assign(plan: plan, occurrences: occurrences)
    |> assign_query(today)
  end

  defp assign_query(%{assigns: %{today: today}} = socket, today), do: socket

  defp assign_query(socket, today) do
    assign(socket,
      today: today,
      query: Ash.Query.for_read(Occurrence, :on_date, %{date: today})
    )
  end

  defp plan(nil, _today, _actor), do: {nil, []}
  defp plan(%{arrival_date: nil}, _today, _actor), do: {:no_arrival, []}

  defp plan(%{arrival_date: arrival}, today, actor) do
    if Date.after?(arrival, today) do
      {{:before_arrival, arrival}, []}
    else
      :ok = Daily.ensure_day(today)

      case Daily.list_occurrences_on!(today, actor: actor) do
        [] ->
          {if(Daily.list_routines!(actor: actor) == [], do: :no_routines, else: :nothing_today),
           []}

        occurrences ->
          {:routines, occurrences}
      end
    end
  end

  defp now, do: Clock.now() |> DateTime.to_naive()
end
