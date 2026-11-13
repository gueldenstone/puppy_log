defmodule PuppyLogWeb.HistoryLive do
  @moduledoc """
  „Verlauf“ (docs/design/Verlauf.dc.html): routine adherence and house
  training over a rolling period (`period` query parameter, see
  `PuppyLog.Daily.Stats.periods/0`, default one week), per routine
  statistics and the way into the day view (`/history/:date`).
  """

  use PuppyLogWeb, :live_view

  alias PuppyLog.{Daily, Clock, Puppy}
  alias PuppyLog.Daily.Stats
  alias PuppyLogWeb.HistoryCharts

  on_mount {PuppyLogWeb.LiveUserAuth, :live_user_required}

  @default_period "1w"
  @topics ~w(occurrences:changed events:changed routines:changed puppy_profile:changed)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Enum.each(@topics, &PuppyLogWeb.Endpoint.subscribe/1)

    {:ok, assign(socket, page_title: "Verlauf", periods: Stats.periods())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    keys = Enum.map(Stats.periods(), &elem(&1, 0))
    period = if params["period"] in keys, do: params["period"], else: @default_period

    {:noreply, socket |> assign(period: period) |> load()}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{}, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    actor = socket.assigns.current_user
    today = Clock.today()
    profile = Puppy.get_profile!(actor: actor)

    state =
      case profile do
        %{arrival_date: %Date{} = arrival} ->
          if Date.after?(arrival, today), do: {:before_arrival, arrival}, else: :ready

        _no_arrival ->
          :no_arrival
      end

    stats = if state == :ready, do: Stats.compute(socket.assigns.period, actor: actor)

    active_routine_ids =
      if state == :ready,
        do: actor |> then(&Daily.list_routines!(actor: &1)) |> MapSet.new(& &1.id),
        else: MapSet.new()

    assign(socket,
      today: today,
      state: state,
      stats: stats,
      active_routine_ids: active_routine_ids
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} tab={:history}>
      <.page_title
        title="Verlauf"
        subtitle={
          if @stats,
            do: Format.date_range(@stats.range.first, @stats.range.last),
            else: "Routinen und Stubenreinheit"
        }
      />

      <%= case @state do %>
        <% :no_arrival -> %>
          <.empty_state icon="clock" title="Wann zieht euer Welpe ein?">
            Tragt im Profil das Einzugsdatum ein, dann seht ihr hier ab diesem Tag, wie gut eure Routinen klappen.
            <:action>
              <.action_button variant={:secondary} navigate={~p"/profile/edit"}>
                Einzugsdatum eintragen
              </.action_button>
            </:action>
          </.empty_state>
        <% {:before_arrival, date} -> %>
          <.empty_state icon="clock" title="Bald geht es los">
            Ab dem Einzug am {Format.long_date(date)} seht ihr hier euren Verlauf.
            <:action>
              <.action_button variant={:secondary} navigate={~p"/routines"}>
                Tagesablauf vorbereiten
              </.action_button>
            </:action>
          </.empty_state>
        <% :ready -> %>
          <.period_chips periods={@periods} period={@period} />
          <.adherence_card stats={@stats} />
          <.potty_card stats={@stats} />
          <.routines_card routines={@stats.routines} active_ids={@active_routine_ids} />

          <.action_button variant={:secondary} navigate={~p"/history/#{Date.to_iso8601(@today)}"}>
            Heute ansehen <.pl_icon name="right" class="size-5" />
          </.action_button>
      <% end %>
    </Layouts.app>
    """
  end

  attr :periods, :list, required: true
  attr :period, :string, required: true

  defp period_chips(assigns) do
    ~H"""
    <nav
      aria-label="Zeitraum"
      class="-mx-4 flex gap-2 overflow-x-auto px-4 pb-0.5 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
    >
      <.link
        :for={{key, label} <- @periods}
        patch={~p"/history?period=#{key}"}
        aria-current={key == @period && "page"}
        class={[
          "flex h-9 shrink-0 items-center rounded-full border px-3.5 text-[14px] font-semibold whitespace-nowrap transition active:scale-95",
          if(key == @period,
            do: "border-accent bg-accent text-white",
            else: "border-line bg-card text-muted hover:border-accent/40 hover:text-ink"
          )
        ]}
      >
        {label}
      </.link>
    </nav>
    """
  end

  attr :stats, :map, required: true

  defp adherence_card(assigns) do
    ~H"""
    <.card class="!pb-3">
      <div class="flex items-baseline justify-between gap-2">
        <h2 class="text-[13px] leading-[18px] font-medium text-muted">Routinen eingehalten</h2>
        <span class="font-display text-[26px] leading-[30px] font-semibold tabular-nums">
          {if @stats.rate, do: "#{@stats.rate} %", else: "–"}
        </span>
      </div>
      <p class="text-[12.5px] text-muted">
        <%= if @stats.counted > 0 do %>
          {@stats.kept} von {@stats.counted} pünktlich (± 15 Min)
        <% else %>
          Noch keine erledigten oder verpassten Routinen
        <% end %>
      </p>
      <HistoryCharts.adherence_bars buckets={@stats.buckets} />
    </.card>
    """
  end

  attr :stats, :map, required: true

  defp potty_card(assigns) do
    ~H"""
    <.card>
      <h2 class="mb-2.5 text-[13px] leading-[18px] font-medium text-muted">Stubenreinheit</h2>
      <div class="flex items-center gap-3">
        <span class={[
          "grid size-11 shrink-0 place-items-center rounded-full",
          if(@stats.accidents > 0,
            do: "bg-danger-tint text-danger",
            else: "bg-accent-tint text-accent"
          )
        ]}>
          <.pl_icon name={if @stats.accidents > 0, do: "alert", else: "check"} class="size-5" />
        </span>
        <div class="min-w-0 flex-1">
          <p class="font-display text-[28px] leading-[34px] font-semibold tabular-nums">
            {@stats.accidents}
          </p>
          <p class="text-[13px] text-muted">
            {if @stats.accidents == 1, do: "Unfall drinnen", else: "Unfälle drinnen"}
          </p>
        </div>
        <.chip :if={@stats.previous_accidents} kind={trend(@stats)} class="tabular-nums">
          Vorher: {@stats.previous_accidents}
        </.chip>
      </div>
      <div class="mt-3.5 flex flex-col gap-3 border-t border-divider pt-3">
        <HistoryCharts.split_bar title="Pipi" icon="pipi" color="text-pipi" counts={@stats.pee} />
        <HistoryCharts.split_bar title="Kaka" icon="kaka" color="text-kaka" counts={@stats.poo} />
        <p class="text-[13px] text-muted">Nichts gemacht: {@stats.nothing}</p>
      </div>
    </.card>
    """
  end

  defp trend(%{accidents: now, previous_accidents: before}) when now < before, do: :ok
  defp trend(%{accidents: now, previous_accidents: before}) when now > before, do: :bad
  defp trend(_stats), do: :neutral

  attr :routines, :list, required: true
  attr :active_ids, :any, required: true, doc: "MapSet of routine ids that can still be edited"

  defp routines_card(assigns) do
    ~H"""
    <.card id="history-routines" class="!pb-1.5">
      <div class="mb-1 flex items-center justify-between">
        <h2 class="text-[13px] leading-[18px] font-medium text-muted">Routinen</h2>
        <.link
          navigate={~p"/routines"}
          class="-my-2 flex min-h-11 items-center gap-1 text-[14px] font-semibold text-accent"
        >
          <.pl_icon name="edit" class="size-4" /> Bearbeiten
        </.link>
      </div>
      <div :if={@routines == []} class="flex flex-col items-start gap-1 py-2">
        <p class="text-[14px] text-muted">In diesem Zeitraum war keine Routine geplant.</p>
        <.link
          navigate={~p"/routines"}
          class="-ml-1 flex min-h-11 items-center px-1 text-[14px] font-semibold text-accent"
        >
          Tagesablauf anlegen
        </.link>
      </div>
      <.routine_stat_row
        :for={routine <- @routines}
        routine={routine}
        editable={MapSet.member?(@active_ids, routine.routine_id)}
      />
    </.card>
    """
  end

  attr :routine, :map, required: true
  attr :editable, :boolean, required: true

  defp routine_stat_row(%{editable: true} = assigns) do
    ~H"""
    <.link
      navigate={~p"/routines/#{@routine.routine_id}"}
      class="-mx-2 flex items-start gap-3 rounded-xl border-t border-divider px-2 py-2.5 transition first-of-type:border-t-0 hover:bg-canvas active:bg-mist"
    >
      <.routine_stat_body routine={@routine} />
      <.pl_icon name="right" class="mt-0.5 size-4 shrink-0 text-muted/70" />
    </.link>
    """
  end

  defp routine_stat_row(assigns) do
    ~H"""
    <div class="flex items-start gap-3 border-t border-divider py-2.5 first-of-type:border-t-0">
      <.routine_stat_body routine={@routine} />
    </div>
    """
  end

  attr :routine, :map, required: true

  defp routine_stat_body(assigns) do
    ~H"""
    <div class="min-w-0 flex-1">
      <p class="truncate text-[15px] leading-5 font-medium">{@routine.name}</p>
      <p class="text-[12.5px] leading-[17px] text-muted">
        {[
          "eingehalten #{@routine.kept} von #{@routine.counted}",
          deviation(@routine.avg_deviation)
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" · ")}
      </p>
      <p :if={misses(@routine)} class="text-[12.5px] leading-[17px] font-semibold text-warn">
        {misses(@routine)}
      </p>
    </div>
    <.chip :if={@routine.rate} kind={rate_kind(@routine.rate)} class="tabular-nums">
      {@routine.rate} %
    </.chip>
    """
  end

  @doc false
  def deviation(nil), do: nil
  def deviation(0), do: "pünktlich"
  def deviation(minutes) when minutes > 0, do: "Ø #{Format.duration(minutes)} zu spät"
  def deviation(minutes), do: "Ø #{Format.duration(-minutes)} zu früh"

  defp misses(routine) do
    [
      routine.skipped > 0 && "#{routine.skipped}× übersprungen",
      routine.missed > 0 && "#{routine.missed}× verpasst"
    ]
    |> Enum.filter(& &1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp rate_kind(rate) when rate >= 80, do: :ok
  defp rate_kind(rate) when rate >= 50, do: :warn
  defp rate_kind(_rate), do: :bad
end
