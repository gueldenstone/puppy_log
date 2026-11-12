defmodule Mix.Tasks.PuppyLog.User.Create do
  @shortdoc "Creates a household member"

  @moduledoc """
  Creates a user. There is no self sign-up.

      mix puppy_log.user.create lisa@example.com --name Lisa
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(args) do
    case OptionParser.parse(args, strict: [name: :string]) do
      {opts, [email], []} ->
        case PuppyLog.Accounts.MagicLinks.create_user(email, opts[:name]) do
          {:ok, user} -> Mix.shell().info("Created user #{user.email} (#{user.id})")
          {:error, error} -> Mix.raise("Could not create user: #{Exception.message(error)}")
        end

      _ ->
        Mix.raise("Usage: mix puppy_log.user.create EMAIL [--name NAME]")
    end
  end
end
