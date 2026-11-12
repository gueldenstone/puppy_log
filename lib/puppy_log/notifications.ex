defmodule PuppyLog.Notifications do
  @moduledoc """
  Web Push subscriptions and delivery.
  """

  use Ash.Domain, otp_app: :puppy_log, extensions: [AshAdmin.Domain]

  admin do
    show? true
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
