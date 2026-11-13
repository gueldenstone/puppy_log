defmodule PuppyLog.Notifications do
  @moduledoc """
  Web Push subscriptions and delivery.
  """

  use Ash.Domain, otp_app: :puppy_log, extensions: [AshAdmin.Domain]

  require Ash.Query

  alias PuppyLog.Notifications.{Push, PushSubscription}

  admin do
    show? true
  end

  @doc "Internal: sends `payload` to every device of the given users."
  @spec deliver_to_users([Ecto.UUID.t()], map) :: [Push.result()]
  def deliver_to_users([], _payload), do: []

  def deliver_to_users(user_ids, payload) when is_list(user_ids) do
    PushSubscription
    |> Ash.Query.filter(user_id in ^user_ids)
    |> Ash.read!(authorize?: false)
    |> Enum.map(&Push.deliver(&1, payload))
  end

  resources do
    resource PuppyLog.Notifications.PushSubscription do
      define :subscribe_push, action: :subscribe
      define :list_push_subscriptions, action: :read
      define :unsubscribe_push, action: :unsubscribe, get_by: [:endpoint]
      define :send_test_push, action: :send_test, args: [:target]
    end
  end
end
