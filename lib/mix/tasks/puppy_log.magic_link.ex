defmodule Mix.Tasks.PuppyLog.MagicLink do
  @shortdoc "Prints a sign-in link for a user"

  @moduledoc """
  Prints a magic sign-in link (valid 24 hours, single use).

      mix puppy_log.magic_link lisa@example.com
      mix puppy_log.magic_link lisa@example.com --base-url https://puppy.example.com
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(args) do
    case OptionParser.parse(args, strict: [base_url: :string]) do
      {opts, [email], []} ->
        case PuppyLog.Accounts.MagicLinks.url_for(email, opts[:base_url]) do
          {:ok, url} -> Mix.shell().info(url)
          {:error, error} -> Mix.raise("Could not create link: #{inspect(error)}")
        end

      _ ->
        Mix.raise("Usage: mix puppy_log.magic_link EMAIL [--base-url URL]")
    end
  end
end
