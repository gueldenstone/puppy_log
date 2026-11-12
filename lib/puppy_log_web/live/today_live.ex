defmodule PuppyLogWeb.TodayLive do
  @moduledoc "Start screen „Heute“ (docs/design/Main.dc.html, entwuerfe/01)."

  use PuppyLogWeb, :live_view

  alias PuppyLog.{Accounts, Clock, Puppy}
  alias PuppyLog.Puppy.{Age, Weight}

  on_mount {PuppyLogWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PuppyLogWeb.Endpoint.subscribe("puppy_profile:changed")
      PuppyLogWeb.Endpoint.subscribe("weight_entries:changed")
    end

    {:ok, socket |> assign(page_title: "Heute") |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} tab={:today}>
      <header class="flex items-center gap-3 px-1">
        <.link
          navigate={if @profile, do: ~p"/profil", else: ~p"/profil/bearbeiten"}
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
          navigate={~p"/einstellungen"}
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
        <.action_button navigate={~p"/profil/bearbeiten"}>Welpenprofil anlegen</.action_button>
      </.card>

      <.empty_state icon="clock" title="Routinen kommen als Nächstes">
        Hier stehen bald eure Tagesroutinen zum Abhaken, mit Erinnerungen auf beiden Handys.
      </.empty_state>

      <section class="flex flex-col gap-2">
        <.section_label>Schnell eintragen</.section_label>
        <div class="grid grid-cols-4 gap-2">
          <.link
            navigate={~p"/gewicht/neu"}
            class="flex min-h-[84px] flex-col items-center justify-center gap-1.5 rounded-[14px] border border-line bg-card text-[13px] font-semibold transition active:scale-95"
          >
            <span class="grid size-9 place-items-center rounded-full bg-mist">
              <.pl_icon name="scale" class="size-5" />
            </span>
            Wiegen
          </.link>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{}, socket), do: {:noreply, load(socket)}

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

    assign(socket, profile: profile, subtitle: subtitle, household: household)
  end
end
