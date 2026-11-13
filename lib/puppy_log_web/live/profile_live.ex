defmodule PuppyLogWeb.ProfileLive do
  @moduledoc "Puppy profile (entwuerfe/02)."

  use PuppyLogWeb, :live_view

  alias PuppyLog.{Clock, Puppy}
  alias PuppyLog.Puppy.{Age, Weight}

  on_mount {PuppyLogWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PuppyLogWeb.Endpoint.subscribe("puppy_profile:changed")
      PuppyLogWeb.Endpoint.subscribe("weight_entries:changed")
    end

    case load(socket) do
      %{assigns: %{profile: nil}} -> {:ok, push_navigate(socket, to: ~p"/profile/edit")}
      socket -> {:ok, assign(socket, page_title: socket.assigns.profile.name)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.top_bar title="Profil" back={~p"/"}>
        <:actions>
          <.link
            navigate={~p"/profile/edit"}
            class="flex min-h-11 items-center gap-1 px-1 text-[14px] font-semibold text-accent"
          >
            <.pl_icon name="edit" class="size-[18px]" /> Bearbeiten
          </.link>
        </:actions>
      </.top_bar>

      <section class="flex flex-col items-center gap-1 pt-2 pb-1 text-center">
        <.puppy_photo profile={@profile} size="size-32" icon_class="size-14" />
        <h2 class="mt-2 font-display text-[26px] leading-[30px] font-semibold">{@profile.name}</h2>
        <p :if={@profile.birth_date} class="text-[14px] text-muted">
          {Age.describe(@profile.birth_date, @today)} alt · geboren am {Format.long_date(
            @profile.birth_date
          )}
        </p>
      </section>

      <.card flush>
        <dl class="divide-y divide-divider">
          <div class="px-4 py-2.5">
            <dt class="text-[12.5px] text-muted">Rasse</dt>
            <dd class="font-medium">{@profile.breed || "–"}</dd>
          </div>
          <div class="flex items-center gap-2 px-4 py-2.5">
            <div class="min-w-0 flex-1">
              <dt class="text-[12.5px] text-muted">Chipnummer</dt>
              <dd class="font-medium tabular-nums tracking-wide" id="chip-number">
                {Format.chip_number(@profile.chip_number) || "–"}
              </dd>
            </div>
            <button
              :if={@profile.chip_number}
              type="button"
              id="copy-chip"
              phx-click={JS.dispatch("puppy:copy", detail: %{text: @profile.chip_number})}
              class="-mr-2 grid size-11 place-items-center rounded-full text-accent active:bg-mist"
              aria-label="Chipnummer kopieren"
            >
              <.pl_icon name="copy" class="size-5" />
            </button>
          </div>
          <div class="px-4 py-2.5">
            <dt class="text-[12.5px] text-muted">Geburtsdatum</dt>
            <dd class="font-medium">
              {if @profile.birth_date, do: Format.long_date(@profile.birth_date), else: "–"}
            </dd>
          </div>
          <div class="px-4 py-2.5">
            <dt class="text-[12.5px] text-muted">Einzug</dt>
            <dd class="font-medium">
              {if @profile.arrival_date,
                do: "Eingezogen am #{Format.long_date(@profile.arrival_date)}",
                else: "Einzug noch nicht eingetragen"}
            </dd>
          </div>
        </dl>
      </.card>

      <.link
        navigate={~p"/weight"}
        class="flex items-center gap-3 rounded-2xl border border-line bg-card p-4 transition active:bg-canvas"
      >
        <span class="grid size-10 place-items-center rounded-full bg-accent-tint text-accent">
          <.pl_icon name="scale" class="size-[22px]" />
        </span>
        <div class="min-w-0 flex-1">
          <p class="text-[13px] font-medium text-muted">Gewicht</p>
          <p class="font-semibold">
            <%= if @summary.latest do %>
              {Weight.to_kg_string(@summary.latest.weight_grams)} kg<span :if={@summary.change_grams}> · {Weight.format_delta(
                @summary.change_grams
              )}</span>
            <% else %>
              Noch nicht gewogen
            <% end %>
          </p>
        </div>
        <.pl_icon name="right" class="size-5 text-muted" />
      </.link>

      <p :if={@profile.updated_by} class="text-center text-[12.5px] text-muted">
        Zuletzt geändert von {Format.who(@profile.updated_by, @current_user)} am {Format.long_date(
          Clock.local(@profile.updated_at)
          |> DateTime.to_date()
        )}
      </p>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{}, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    actor = socket.assigns.current_user

    assign(socket,
      profile: Puppy.get_profile!(actor: actor, load: [:updated_by]),
      summary: Puppy.weight_summary(actor: actor),
      today: Clock.today()
    )
  end
end
