defmodule PuppyLogWeb.PlaceholderLive do
  @moduledoc "Tabs that are not built yet: „Verlauf“ and „Lernen“."

  use PuppyLogWeb, :live_view

  on_mount {PuppyLogWeb.LiveUserAuth, :live_user_required}

  @pages %{
    history: %{
      title: "Verlauf",
      subtitle: "Routinen, Stubenreinheit und Ereignisse",
      icon: "chart",
      text:
        "Sobald ihr Routinen und Ereignisse eintragt, seht ihr hier die Auswertung pro Tag und Woche."
    },
    learn: %{
      title: "Lernen",
      subtitle: "Sozialisierung und Kommandos",
      icon: "book",
      text: "Hier entstehen eure Sozialisierungs-Checkliste und der Lernstand der Kommandos."
    }
  }

  @impl true
  def mount(_params, _session, socket) do
    page = Map.fetch!(@pages, socket.assigns.live_action)
    {:ok, assign(socket, page: page, page_title: page.title)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} tab={@live_action}>
      <.page_title title={@page.title} subtitle={@page.subtitle} />
      <.empty_state icon={@page.icon} title="Kommt in einem der nächsten Schritte">
        {@page.text}
      </.empty_state>
    </Layouts.app>
    """
  end
end
