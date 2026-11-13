defmodule PuppyLogWeb.UI do
  @moduledoc """
  Building blocks of the Puppy Log design (docs/design/DESIGN.md).

  Colors and fonts come from the Tailwind theme in `assets/css/app.css`
  (`bg-canvas`, `text-muted`, `bg-accent`, `font-display`, …).
  """

  use Phoenix.Component
  use Gettext, backend: PuppyLogWeb.Gettext

  alias Phoenix.LiveView.JS

  # Icons --------------------------------------------------------------------

  @icons %{
    "home" => ~s(<path d="M3 10.5L12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>),
    "chart" => ~s(<path d="M6 20v-8M12 20V4M18 20V9"/>),
    "heart" =>
      ~s(<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1-1.1a5.5 5.5 0 0 0-7.8 7.8l1 1.1L12 21l7.8-7.5 1-1.1a5.5 5.5 0 0 0 0-7.8z"/>),
    "book" =>
      ~s(<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20V3H6.5A2.5 2.5 0 0 0 4 5.5z"/><path d="M4 19.5A2.5 2.5 0 0 0 6.5 22H20v-5"/>),
    "pipi" => ~s(<path d="M12 2.7l5.7 5.7a8 8 0 1 1-11.4 0z"/>),
    "kaka" =>
      ~s(<path d="M8 20h8a2 2 0 0 0 0-4H8a2 2 0 0 0 0 4z M9 15h6a2 2 0 0 0 0-4H9a2 2 0 0 0 0 4z M11 10h2a2 2 0 0 0 0-4h-2a2 2 0 0 0 0 4z"/>),
    "bowl" => ~s(<path d="M3 11h18a9 9 0 0 1-18 0z"/>),
    "gassi" =>
      ~s(<path d="M12 21s-7-6.2-7-11a7 7 0 0 1 14 0c0 4.8-7 11-7 11z"/><circle cx="12" cy="10" r="2"/>),
    "paw" =>
      ~s(<circle cx="6" cy="10" r="2"/><circle cx="10" cy="6" r="2"/><circle cx="14" cy="6" r="2"/><circle cx="18" cy="10" r="2"/><path d="M12 12c-3 0-5 3-5 5.5 0 1.5 1.2 2.5 2.7 2.5 1 0 1.5-.5 2.3-.5s1.3.5 2.3.5c1.5 0 2.7-1 2.7-2.5C17 15 15 12 12 12z"/>),
    "plus" => ~s(<path d="M12 5v14M5 12h14"/>),
    "check" => ~s(<path d="M20 6L9 17l-5-5"/>),
    "x" => ~s(<path d="M6 6l12 12M18 6L6 18"/>),
    "left" => ~s(<path d="M15 6l-6 6 6 6"/>),
    "right" => ~s(<path d="M9 6l6 6-6 6"/>),
    "edit" => ~s(<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z"/>),
    "trash" => ~s(<path d="M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6"/>),
    "camera" =>
      ~s(<path d="M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2z"/><circle cx="12" cy="13" r="4"/>),
    "scale" => ~s(<path d="M9 7a3 3 0 1 1 6 0"/><path d="M6.5 9h11l2 11h-15z"/>),
    "copy" =>
      ~s(<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>),
    "download" =>
      ~s(<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M7 10l5 5 5-5M12 15V3"/>),
    "bell" =>
      ~s(<path d="M18 8a6 6 0 0 0-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.7 21a2 2 0 0 1-3.4 0"/>),
    "logout" => ~s(<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9"/>),
    "phone" => ~s(<rect x="6" y="2" width="12" height="20" rx="2"/><path d="M11 18h2"/>),
    "send" => ~s(<path d="M22 2L11 13"/><path d="M22 2l-7 20-4-9-9-4z"/>),
    "skip" => ~s(<path d="M5 4l10 8-10 8z"/><path d="M19 5v14"/>),
    "undo" => ~s(<path d="M9 14L4 9l5-5"/><path d="M4 9h11a5 5 0 0 1 0 10h-3"/>),
    "clock" => ~s(<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>),
    "sparkle" =>
      ~s(<path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5L18 18M6 18l2.5-2.5M15.5 8.5L18 6"/>)
  }

  @doc "Stroke icon from the design (2 px, rounded, 24 px grid)."
  attr :name, :string, required: true
  attr :class, :any, default: "size-6"
  attr :stroke_width, :any, default: 2
  attr :rest, :global

  def pl_icon(assigns) do
    assigns = assign(assigns, :paths, Map.fetch!(@icons, assigns.name))

    ~H"""
    <svg
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width={@stroke_width}
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      {@rest}
    >
      {Phoenix.HTML.raw(@paths)}
    </svg>
    """
  end

  # Surfaces -----------------------------------------------------------------

  @doc "White card with border, radius 16."
  attr :flush, :boolean, default: false, doc: "no padding, for lists of rows"
  attr :class, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section
      class={[
        "rounded-2xl border border-line bg-card",
        if(@flush, do: "overflow-hidden", else: "p-4"),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr :class, :any, default: nil
  slot :inner_block, required: true

  def section_label(assigns) do
    ~H"""
    <h2 class={["px-1 text-[13px] leading-[18px] font-medium text-muted", @class]}>
      {render_slot(@inner_block)}
    </h2>
    """
  end

  @doc "Page title for tab pages."
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions

  def page_title(assigns) do
    ~H"""
    <header class="flex items-start gap-3 px-1">
      <div class="min-w-0 flex-1">
        <h1 class="font-display text-[26px] leading-[30px] font-semibold">{@title}</h1>
        <p :if={@subtitle} class="text-[14px] leading-5 text-muted">{@subtitle}</p>
      </div>
      {render_slot(@actions)}
    </header>
    """
  end

  @doc "Header of sub pages and forms: back or close button, title, actions."
  attr :title, :string, required: true
  attr :back, :string, default: nil, doc: "navigate target of the back arrow"
  attr :close, :string, default: nil, doc: "navigate target of the close cross"
  slot :actions

  def top_bar(assigns) do
    ~H"""
    <header class="-mx-2 flex min-h-11 items-center gap-1">
      <.link
        :if={@back}
        navigate={@back}
        class="grid size-11 place-items-center rounded-full transition active:bg-mist"
        aria-label={gettext("Zurück")}
      >
        <.pl_icon name="left" />
      </.link>
      <.link
        :if={@close}
        navigate={@close}
        class="grid size-11 place-items-center rounded-full transition active:bg-mist"
        aria-label={gettext("Schließen")}
      >
        <.pl_icon name="x" />
      </.link>
      <h1 class="flex-1 truncate font-display text-[22px] leading-7 font-semibold">{@title}</h1>
      {render_slot(@actions)}
    </header>
    """
  end

  # Small parts ----------------------------------------------------------------

  attr :kind, :atom, default: :neutral, values: [:ok, :warn, :bad, :neutral, :pipi, :kaka]
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def chip(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center gap-1 whitespace-nowrap rounded-[10px] px-2.5 py-[3px] text-[12px] font-semibold",
      chip_colors(@kind),
      @class
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp chip_colors(:ok), do: "bg-accent-tint text-accent"
  defp chip_colors(:warn), do: "bg-warn-tint text-warn"
  defp chip_colors(:bad), do: "bg-danger-tint text-danger"
  defp chip_colors(:neutral), do: "bg-mist text-muted"
  defp chip_colors(:pipi), do: "bg-pipi-tint text-pipi"
  defp chip_colors(:kaka), do: "bg-kaka-tint text-kaka"

  attr :value, :integer, required: true, doc: "0..100"
  attr :label, :string, required: true, doc: "accessible description"
  attr :class, :any, default: nil

  def progress(assigns) do
    ~H"""
    <div
      class={["h-2 overflow-hidden rounded bg-mist", @class]}
      role="progressbar"
      aria-label={@label}
      aria-valuemin="0"
      aria-valuemax="100"
      aria-valuenow={@value}
    >
      <div
        class="h-full rounded bg-accent transition-[width] duration-300"
        style={"width: #{@value}%"}
      />
    </div>
    """
  end

  @doc "Primary (filled) or secondary (outlined) action, as button or link."
  attr :variant, :atom, default: :primary, values: [:primary, :secondary, :danger]
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :href, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global, include: ~w(type disabled form name value)
  slot :inner_block, required: true

  def action_button(%{navigate: nil, patch: nil, href: nil} = assigns) do
    ~H"""
    <button class={[button_class(@variant), @class]} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  def action_button(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      patch={@patch}
      href={@href}
      class={[button_class(@variant), @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp button_class(variant) do
    [
      "flex h-[52px] w-full items-center justify-center gap-2 rounded-[14px] text-base font-semibold",
      "transition active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-50",
      "phx-submit-loading:opacity-70",
      case variant do
        :primary -> "bg-accent text-white hover:bg-accent-dark"
        :secondary -> "border-2 border-accent bg-card text-accent hover:bg-accent-tint"
        :danger -> "h-12 text-danger hover:bg-danger-tint"
      end
    ]
  end

  # Puppy and people -------------------------------------------------------------

  @doc "Round puppy photo, paw placeholder when there is none."
  attr :profile, :any, default: nil
  attr :size, :string, default: "size-12"
  attr :icon_class, :string, default: "size-6"

  def puppy_photo(assigns) do
    ~H"""
    <div class={[
      "grid shrink-0 place-items-center overflow-hidden rounded-full bg-accent-tint text-accent",
      @size
    ]}>
      <img
        :if={@profile && @profile.photo_path}
        src={"/uploads/#{@profile.photo_path}"}
        alt={"Foto von #{@profile.name}"}
        class="size-full object-cover"
      />
      <.pl_icon :if={!(@profile && @profile.photo_path)} name="paw" class={@icon_class} />
    </div>
    """
  end

  attr :user, :any, required: true
  attr :current_user, :any, required: true
  attr :class, :any, default: nil

  def avatar(assigns) do
    ~H"""
    <span class={[
      "grid size-8 place-items-center rounded-full border-2 border-canvas text-[12px] font-semibold text-white",
      if(@user.id == @current_user.id, do: "bg-accent", else: "bg-pipi"),
      @class
    ]}>
      {PuppyLogWeb.Format.initials(@user, @current_user)}
    </span>
    """
  end

  # Navigation -----------------------------------------------------------------

  @tabs [
    {:today, "Heute", "home", "/"},
    {:history, "Verlauf", "chart", "/verlauf"},
    {:health, "Gesundheit", "heart", "/gesundheit"},
    {:learn, "Lernen", "book", "/lernen"}
  ]

  attr :active, :atom, default: nil

  def tab_bar(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <nav
      aria-label="Hauptnavigation"
      class="fixed inset-x-0 bottom-0 z-30 border-t border-line bg-card/95 pb-[env(safe-area-inset-bottom)] backdrop-blur-xl"
    >
      <div class="mx-auto grid h-[72px] max-w-xl grid-cols-4">
        <.link
          :for={{key, label, icon, path} <- @tabs}
          navigate={path}
          aria-current={key == @active && "page"}
          class={[
            "flex flex-col items-center justify-center gap-1 text-[12px] transition active:scale-95",
            if(key == @active, do: "font-semibold text-accent", else: "font-medium text-muted")
          ]}
        >
          <.pl_icon name={icon} />
          {label}
        </.link>
      </div>
    </nav>
    """
  end

  # Overlays -------------------------------------------------------------------

  @doc """
  Bottom sheet dialog. Closing (backdrop, Escape, ×) patches to `close`.
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :close, :string, required: true
  slot :inner_block, required: true

  def sheet(assigns) do
    ~H"""
    <div id={@id} class="fixed inset-0 z-40" phx-window-keydown={JS.patch(@close)} phx-key="Escape">
      <button
        type="button"
        phx-click={JS.patch(@close)}
        class="absolute inset-0 bg-ink/40 motion-safe:animate-[fadein_160ms_ease-out]"
        aria-label={gettext("Schließen")}
        tabindex="-1"
      />
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        class="absolute inset-x-0 bottom-0 mx-auto flex max-h-[92dvh] max-w-xl flex-col gap-3.5 overflow-y-auto rounded-t-[20px] bg-canvas px-4 pt-2 pb-[calc(1.5rem+env(safe-area-inset-bottom))] shadow-[0_-8px_30px_rgba(0,0,0,0.18)] motion-safe:animate-[sheetin_220ms_cubic-bezier(.2,.9,.3,1)]"
      >
        <div class="mx-auto mb-1 h-[5px] w-9 rounded-full bg-line" aria-hidden="true" />
        <div class="flex items-center">
          <h2 id={"#{@id}-title"} class="flex-1 font-display text-[22px] leading-7 font-semibold">
            {@title}
          </h2>
          <.link
            patch={@close}
            class="-mr-2 grid size-11 place-items-center rounded-full active:bg-mist"
            aria-label={gettext("Schließen")}
          >
            <.pl_icon name="x" />
          </.link>
        </div>
        {render_slot(@inner_block)}
      </section>
    </div>
    """
  end

  @doc """
  Row that reveals actions by swiping left or long-pressing (hook `SwipeRow`).
  The actions are real buttons and become visible on keyboard focus too.
  """
  attr :id, :string, required: true
  attr :width, :integer, default: 132, doc: "width of the action area in px"
  slot :inner_block, required: true
  slot :actions, required: true

  def swipe_row(assigns) do
    ~H"""
    <div id={@id} class="swipe-row" phx-hook="SwipeRow" style={"--swipe-width: #{@width}px"}>
      <div class="swipe-actions">{render_slot(@actions)}</div>
      <div class="swipe-front bg-card">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :kind, :atom, values: [:accent, :danger, :warn], default: :accent
  attr :icon, :string, required: true
  attr :rest, :global, include: ~w(type disabled)
  slot :inner_block, required: true

  def swipe_action(assigns) do
    ~H"""
    <button
      class={[
        "flex flex-1 flex-col items-center justify-center gap-0.5 text-[13px] font-semibold text-white",
        case @kind do
          :accent -> "bg-accent"
          :danger -> "bg-danger"
          :warn -> "bg-warn"
        end
      ]}
      {@rest}
    >
      <.pl_icon name={@icon} class="size-5" />
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc "Friendly empty state inside a card."
  attr :icon, :string, required: true
  attr :title, :string, required: true
  slot :inner_block
  slot :action

  def empty_state(assigns) do
    ~H"""
    <.card class="flex flex-col items-center gap-2 py-8 text-center">
      <span class="grid size-12 place-items-center rounded-full bg-mist text-muted">
        <.pl_icon name={@icon} />
      </span>
      <p class="font-semibold">{@title}</p>
      <p :if={@inner_block != []} class="max-w-72 text-[14px] text-muted">
        {render_slot(@inner_block)}
      </p>
      <div :if={@action != []} class="mt-2 w-full max-w-64">{render_slot(@action)}</div>
    </.card>
    """
  end
end
