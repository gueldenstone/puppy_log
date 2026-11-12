defmodule PuppyLogWeb.AuthController do
  use PuppyLogWeb, :controller
  use AshAuthentication.Phoenix.Controller

  @remember_me_cookie_options [
    http_only: true,
    secure: Application.compile_env(:puppy_log, :secure_cookies, true),
    same_site: "Lax"
  ]

  @impl AshAuthentication.Phoenix.Controller
  def success(conn, _activity, user, _token) do
    return_to = get_session(conn, :return_to) || ~p"/"

    conn
    |> delete_session(:return_to)
    |> store_in_session(user)
    |> assign(:current_user, user)
    |> put_flash(:info, "Du bist angemeldet.")
    |> redirect(to: return_to)
  end

  @impl AshAuthentication.Phoenix.Controller
  def failure(conn, _activity, _reason) do
    conn
    |> put_flash(
      :error,
      "Der Login-Link ist ungültig, abgelaufen oder wurde schon benutzt. Bitte einen neuen anfordern."
    )
    |> redirect(to: ~p"/sign-in")
  end

  @impl AshAuthentication.Phoenix.Controller
  def sign_out(conn, _params) do
    conn
    |> clear_session(:puppy_log)
    |> put_flash(:info, "Du bist abgemeldet.")
    |> redirect(to: ~p"/sign-in")
  end

  @impl AshAuthentication.Phoenix.Controller
  def put_remember_me_cookie(conn, cookie_name, %{token: token, max_age: max_age}) do
    put_resp_cookie(
      conn,
      cookie_name,
      token,
      Keyword.put(@remember_me_cookie_options, :max_age, max_age)
    )
  end

  @impl AshAuthentication.Phoenix.Controller
  def delete_remember_me_cookie(conn, cookie_name) do
    delete_resp_cookie(conn, cookie_name, @remember_me_cookie_options)
  end
end
