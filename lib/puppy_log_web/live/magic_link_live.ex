defmodule PuppyLogWeb.MagicLinkLive do
  @moduledoc """
  Landing page of a magic link. Signing in needs an explicit tap, so link
  previews in messengers cannot use up the single-use token.
  """

  use PuppyLogWeb, :live_view

  on_mount {PuppyLogWeb.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    {:ok, assign(socket, page_title: "Anmelden", token: token)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <header class="flex flex-col gap-1 px-1 pt-2">
        <span class="mb-2 grid size-14 place-items-center rounded-2xl bg-accent text-white">
          <.pl_icon name="paw" class="size-7" />
        </span>
        <h1 class="font-display text-[26px] leading-[30px] font-semibold">Fast geschafft</h1>
        <p class="text-[14px] text-muted">
          Tippe auf „Anmelden“. Dieses Gerät bleibt danach ein Jahr lang angemeldet.
        </p>
      </header>

      <.form
        for={%{}}
        as={:user}
        id="magic-link-form"
        action={~p"/auth/user/magic_link"}
        method="post"
      >
        <input type="hidden" name="user[token]" value={@token} />
        <input type="hidden" name="user[remember_me]" value="true" />
        <.action_button type="submit">Anmelden</.action_button>
        <p :if={@current_user} class="mt-3 text-center text-[13px] text-muted">
          Du bist bereits als {Format.user_name(@current_user)} angemeldet.
        </p>
      </.form>
    </Layouts.app>
    """
  end
end
