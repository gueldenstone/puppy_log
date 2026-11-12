defmodule Mix.Tasks.PuppyLog.Gen.Vapid do
  @shortdoc "Generates a VAPID key pair for Web Push"

  @moduledoc """
  Generates a VAPID key pair and prints it as environment variables.

      mix puppy_log.gen.vapid

  Keep the keys stable: changing them invalidates every push subscription.
  """

  use Mix.Task

  @impl true
  def run(_args) do
    {public_key, private_key} = :crypto.generate_key(:ecdh, :prime256v1)

    Mix.shell().info("""
    VAPID_PUBLIC_KEY=#{Base.url_encode64(public_key, padding: false)}
    VAPID_PRIVATE_KEY=#{Base.url_encode64(private_key, padding: false)}
    VAPID_SUBJECT=mailto:you@example.com
    """)
  end
end
