defmodule PuppyLog.Notifications.SendTestPush do
  @moduledoc """
  Generic action implementation: sends a test push and reports per-device results.
  """

  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias PuppyLog.Notifications.{Push, PushSubscription}

  @impl true
  def run(input, _opts, context) do
    actor = context.actor
    target = input.arguments.target

    subscriptions =
      PushSubscription
      |> filter_target(target, actor)
      |> Ash.Query.load(:user)
      |> Ash.read!(actor: actor)

    sender = actor.name || to_string(actor.email)

    payload = %{
      title: "Test-Push 🐶",
      body:
        "Gesendet von #{sender} um #{Calendar.strftime(PuppyLog.Clock.now(), "%H:%M:%S")} Uhr",
      tag: "test-push",
      url: "/"
    }

    results =
      Enum.map(subscriptions, fn subscription ->
        %{
          id: subscription.id,
          user: subscription.user.name || to_string(subscription.user.email),
          result: Push.deliver(subscription, payload)
        }
      end)

    {:ok, %{sent: Enum.count(results, &match?(%{result: :ok}, &1)), results: results}}
  end

  defp filter_target(query, :me, actor), do: Ash.Query.filter(query, user_id == ^actor.id)
  defp filter_target(query, :all, _actor), do: query
end
