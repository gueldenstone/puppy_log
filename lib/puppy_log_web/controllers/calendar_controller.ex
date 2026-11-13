defmodule PuppyLogWeb.CalendarController do
  @moduledoc """
  Subscribable iCalendar feed of all household health entries. The secret token
  in the URL is the only authentication (calendar apps cannot sign in).
  """

  use PuppyLogWeb, :controller

  require Ash.Query

  alias PuppyLog.{Accounts, Clock, Puppy}
  alias PuppyLog.Puppy.{Calendar, HealthEntry}

  @days_back 365

  def show(conn, %{"token" => param}) do
    token = String.replace_suffix(param, ".ics", "")

    case Accounts.get_user_by_calendar_token(token, authorize?: false) do
      {:ok, %Accounts.User{}} ->
        conn
        |> put_resp_content_type("text/calendar", "utf-8")
        |> put_resp_header("cache-control", "private, no-cache")
        |> send_resp(200, render_feed())

      _ ->
        send_resp(conn, 404, "")
    end
  end

  defp render_feed do
    since = Date.add(Clock.today(), -@days_back)

    entries =
      HealthEntry
      |> Ash.Query.filter(due_on >= ^since)
      |> Ash.Query.sort(due_on: :asc, due_time: :asc, inserted_at: :asc)
      |> Ash.read!(authorize?: false)

    users =
      for user <- Accounts.list_users!(authorize?: false),
          user.name,
          into: %{},
          do: {user.id, user.name}

    Calendar.render(entries, name: calendar_name(), users: users)
  end

  defp calendar_name do
    case Puppy.get_profile!(authorize?: false) do
      %{name: name} -> "Puppy Log – " <> name
      nil -> "Puppy Log"
    end
  end
end
