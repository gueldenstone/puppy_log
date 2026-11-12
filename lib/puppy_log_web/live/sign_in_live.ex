defmodule PuppyLogWeb.SignInLive do
  @moduledoc """
  Sign-in page. There is no e-mail form: members get a personal magic link
  by message. The paste field exists for the home screen app, which has no
  address bar and does not share cookies with Safari.
  """

  use PuppyLogWeb, :live_view

  on_mount {PuppyLogWeb.LiveUserAuth, :live_no_user}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Anmelden")
     |> assign(form: to_form(%{"link" => ""}, as: :login))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <header class="flex flex-col gap-1 px-1 pt-2">
        <span class="mb-2 grid size-14 place-items-center rounded-2xl bg-accent text-white">
          <.pl_icon name="paw" class="size-7" />
        </span>
        <h1 class="font-display text-[26px] leading-[30px] font-semibold">
          Willkommen bei Puppy Log
        </h1>
        <p class="text-[14px] text-muted">
          Einmal einrichten, danach läuft alles auf euren beiden Handys.
        </p>
      </header>

      <.card class="flex gap-3">
        <span class="grid size-8 shrink-0 place-items-center rounded-full bg-mist text-[14px] font-bold text-muted">
          1
        </span>
        <div>
          <h2 class="font-semibold">Zum Home-Bildschirm hinzufügen</h2>
          <p class="mt-0.5 text-[14px] text-muted">
            In Safari auf „Teilen“ und „Zum Home-Bildschirm“ tippen, dann Puppy Log von dort öffnen.
            Nur so kann das iPhone Erinnerungen zustellen.
          </p>
        </div>
      </.card>

      <.card class="flex gap-3">
        <span class="grid size-8 shrink-0 place-items-center rounded-full bg-accent-tint text-[14px] font-bold text-accent">
          2
        </span>
        <div class="min-w-0 flex-1">
          <h2 class="font-semibold">Anmelden</h2>
          <p class="mt-0.5 text-[14px] text-muted">
            Füge den Login-Link aus deiner Nachricht ein. Dieses Gerät bleibt danach angemeldet.
          </p>

          <.form for={@form} id="login-link-form" phx-submit="submit" class="mt-3 flex flex-col gap-3">
            <.input
              field={@form[:link]}
              type="url"
              label="Login-Link"
              placeholder="https://…/magic_link/…"
              autocomplete="off"
              autocapitalize="off"
              spellcheck="false"
            />
            <.action_button type="submit">Anmelden</.action_button>
          </.form>
        </div>
      </.card>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("submit", %{"login" => %{"link" => link}}, socket) do
    case extract_token(link) do
      {:ok, token} ->
        {:noreply, push_navigate(socket, to: ~p"/magic_link/#{token}")}

      :error ->
        {:noreply,
         assign(socket,
           form:
             to_form(%{"link" => link},
               as: :login,
               errors: [link: {"Das sieht nicht wie ein Login-Link aus.", []}]
             )
         )}
    end
  end

  @jwt ~r/\A[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\z/

  @doc "Accepts a full magic link URL or the bare token."
  @spec extract_token(String.t()) :: {:ok, String.t()} | :error
  def extract_token(input) when is_binary(input) do
    input = String.trim(input)

    token =
      case Regex.run(~r{/magic_link/([^/?#\s]+)}, input) do
        [_, token] -> token
        nil -> input
      end

    if Regex.match?(@jwt, token), do: {:ok, token}, else: :error
  end
end
