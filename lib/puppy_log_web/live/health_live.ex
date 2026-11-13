defmodule PuppyLogWeb.HealthLive do
  @moduledoc "Health tab („Gesundheit“, docs/design/Gesundheit.dc.html): weight card; appointments follow later."

  use PuppyLogWeb, :live_view

  alias PuppyLog.Puppy
  alias PuppyLog.Puppy.Weight
  alias PuppyLogWeb.WeightChart

  on_mount {PuppyLogWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PuppyLogWeb.Endpoint.subscribe("puppy_profile:changed")
      PuppyLogWeb.Endpoint.subscribe("weight_entries:changed")
    end

    {:ok, socket |> assign(page_title: "Gesundheit") |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} tab={:health}>
      <.page_title title="Gesundheit" subtitle="Impfungen, Vorsorge und Gewicht" />

      <.card id="weight-card">
        <div class="flex items-center justify-between">
          <h2 class="text-[13px] font-medium text-muted">Gewicht</h2>
          <.link
            navigate={~p"/weight/new"}
            class="-my-2 flex min-h-11 items-center text-[14px] font-semibold text-accent"
          >
            Wiegen eintragen
          </.link>
        </div>
        <.link navigate={~p"/weight"} class="block" aria-label="Alle Gewichtseinträge anzeigen">
          <div :if={@summary.latest} class="mt-0.5 flex flex-wrap items-baseline gap-x-2">
            <span class="font-display text-[28px] leading-[34px] font-semibold">
              {Weight.to_kg_string(@summary.latest.weight_grams)} kg
            </span>
            <span :if={@summary.change_grams} class="text-[13px] text-muted">
              {Weight.format_delta(@summary.change_grams)} seit {Format.short_date(
                @summary.previous.measured_on
              )}
            </span>
          </div>
          <p :if={!@summary.latest} class="py-4 text-[14px] text-muted">
            Noch nicht gewogen.
          </p>
          <div :if={@summary.latest} class="mt-2">
            <WeightChart.chart entries={@entries} birth_date={@profile && @profile.birth_date} />
          </div>
        </.link>
      </.card>

      <.empty_state icon="heart" title="Impfungen und Vorsorge kommen als Nächstes">
        Termine tragt ihr selbst ein, mit Erinnerung ein paar Tage vorher.
      </.empty_state>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{}, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    actor = socket.assigns.current_user

    assign(socket,
      profile: Puppy.get_profile!(actor: actor),
      summary: Puppy.weight_summary(actor: actor),
      entries: Puppy.list_weights!(actor: actor)
    )
  end
end
