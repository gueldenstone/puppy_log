defmodule PuppyLogWeb.CinderTheme do
  @moduledoc "Cinder theme in the Puppy Log design (cards, dividers, tokens)."

  use Cinder.Theme

  set :container_class, ""
  set :controls_class, "mb-3"

  set :table_wrapper_class, "overflow-x-auto rounded-2xl border border-line bg-card"
  set :table_class, "w-full text-[15px]"
  set :th_class, "px-4 py-3 text-left text-[13px] font-medium text-muted"
  set :td_class, "px-4 py-3 border-t border-divider"

  set :list_container_class,
      "overflow-hidden rounded-2xl border border-line bg-card divide-y divide-divider"

  set :list_item_class, "text-ink"
  set :list_item_clickable_class, "cursor-pointer active:bg-canvas transition-colors"

  set :empty_class, "rounded-2xl border border-line bg-card px-4 py-8 text-center text-muted"
  set :error_container_class, "rounded-2xl bg-danger-tint px-4 py-3 text-danger font-semibold"

  set :loading_overlay_class, "absolute top-3 right-3"
  set :loading_container_class, "flex items-center text-[13px] text-muted"
  set :loading_spinner_class, "animate-spin size-4 mr-2 text-accent"

  set :pagination_wrapper_class, "pt-3"
  set :pagination_container_class, "flex items-center justify-between"
  set :pagination_info_class, "text-[13px] text-muted"
  set :pagination_nav_class, "flex items-center gap-1"

  set :pagination_button_class,
      "min-h-11 min-w-11 rounded-xl border border-line bg-card px-3 text-[14px] font-semibold"

  set :pagination_current_class,
      "min-h-11 min-w-11 rounded-xl bg-accent px-3 text-[14px] font-semibold text-white"
end
