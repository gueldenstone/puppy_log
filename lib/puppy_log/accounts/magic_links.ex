defmodule PuppyLog.Accounts.MagicLinks do
  @moduledoc """
  Admin helpers to create household members and hand out sign-in links
  without sending e-mail.

  Usable from mix tasks in development and from a release:

      bin/puppy_log rpc 'PuppyLog.Accounts.MagicLinks.print("lisa@example.com")'
  """

  alias AshAuthentication.{Info, Strategy.MagicLink}
  alias PuppyLog.Accounts

  @doc "Creates a user (bypassing authorization, admin use only)."
  @spec create_user(String.t(), String.t() | nil) :: {:ok, Ash.Resource.record()} | {:error, term}
  def create_user(email, name \\ nil) do
    Accounts.create_user(email, %{name: name}, authorize?: false)
  end

  @doc """
  Generates a sign-in URL for an existing user.

  `base_url` defaults to the endpoint URL, pass the public URL (e.g. a tunnel)
  when it differs.
  """
  @spec url_for(String.t(), String.t() | nil) :: {:ok, String.t()} | {:error, term}
  def url_for(email, base_url \\ nil) do
    strategy = Info.strategy!(Accounts.User, :magic_link)

    with {:ok, user} <- Accounts.get_user_by_email(email, authorize?: false),
         {:ok, token} <- request_token(strategy, user) do
      base = String.trim_trailing(base_url || PuppyLogWeb.Endpoint.url(), "/")
      {:ok, "#{base}/magic_link/#{token}"}
    end
  end

  @doc "Prints a sign-in URL, convenient for `bin/puppy_log rpc`."
  @spec print(String.t(), String.t() | nil) :: :ok
  def print(email, base_url \\ nil) do
    case url_for(email, base_url) do
      {:ok, url} -> IO.puts(url)
      {:error, error} -> IO.puts(:stderr, "Could not create link: #{inspect(error)}")
    end
  end

  defp request_token(strategy, user) do
    case MagicLink.request_token_for(strategy, user) do
      {:ok, token} -> {:ok, token}
      :error -> {:error, :token_generation_failed}
    end
  end
end
