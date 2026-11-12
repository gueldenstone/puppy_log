defmodule PuppyLogWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use PuppyLogWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_user, :map, default: nil, doc: "the signed in user, if any"

  attr :tab, :atom,
    default: nil,
    doc: "active tab (:today, :history, :health, :learn); nil hides the tab bar"

  slot :inner_block, required: true
  slot :footer, doc: "sticky bottom area, e.g. the primary action of a form"

  def app(assigns) do
    ~H"""
    <div class="min-h-dvh bg-canvas text-ink">
      <main class={[
        "mx-auto flex max-w-xl flex-col gap-3 px-4 pt-[calc(1.5rem+2px+env(safe-area-inset-top))]",
        cond do
          @tab -> "pb-[calc(72px+1.5rem+env(safe-area-inset-bottom))]"
          @footer != [] -> "pb-[calc(76px+1.5rem+env(safe-area-inset-bottom))]"
          true -> "pb-[calc(1.5rem+env(safe-area-inset-bottom))]"
        end
      ]}>
        {render_slot(@inner_block)}
      </main>

      <div
        :if={@footer != []}
        class="fixed inset-x-0 bottom-0 z-20 bg-gradient-to-t from-canvas via-canvas/95 to-canvas/0 pt-6 pb-[calc(1.5rem+env(safe-area-inset-bottom))]"
      >
        <div class="mx-auto max-w-xl px-4">{render_slot(@footer)}</div>
      </div>

      <PuppyLogWeb.UI.tab_bar :if={@tab} active={@tab} />
      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        auto_dismiss={false}
        title={gettext("Keine Verbindung")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Verbinde neu …")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        auto_dismiss={false}
        title={gettext("Etwas ist schiefgelaufen")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Verbinde neu …")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
