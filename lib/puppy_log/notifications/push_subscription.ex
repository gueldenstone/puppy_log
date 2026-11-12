defmodule PuppyLog.Notifications.PushSubscription do
  @moduledoc """
  A browser push subscription (one per device / installed PWA).
  """

  use Ash.Resource,
    otp_app: :puppy_log,
    domain: PuppyLog.Notifications,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  sqlite do
    table "push_subscriptions"
    repo PuppyLog.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :subscribe do
      description "Registers (or refreshes) the push subscription of the current device."
      accept [:endpoint, :p256dh, :auth, :user_agent]
      upsert? true
      upsert_identity :unique_endpoint
      upsert_fields [:p256dh, :auth, :user_agent, :user_id, :updated_at]
      change relate_actor(:user)
    end

    destroy :unsubscribe do
      description "Removes the subscription of the current device."
    end

    destroy :expire do
      description "Removes a subscription the push service reported as gone."
    end

    action :send_test, :map do
      description "Sends a test notification to the actor's devices or to everybody."

      argument :target, :atom do
        allow_nil? false
        constraints one_of: [:me, :all]
      end

      run PuppyLog.Notifications.SendTestPush
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action([:subscribe, :send_test]) do
      authorize_if actor_present()
    end

    policy action(:unsubscribe) do
      authorize_if relates_to_actor_via(:user)
    end

    # :expire is internal only and called with authorize?: false
    policy action(:expire) do
      forbid_if always()
    end
  end

  pub_sub do
    module PuppyLogWeb.Endpoint
    prefix "push_subscriptions"

    publish_all :create, "changed"
    publish_all :destroy, "changed"
  end

  attributes do
    uuid_primary_key :id

    attribute :endpoint, :string do
      allow_nil? false
      public? true
    end

    attribute :p256dh, :string do
      allow_nil? false
      public? true
      sensitive? true
    end

    attribute :auth, :string do
      allow_nil? false
      public? true
      sensitive? true
    end

    attribute :user_agent, :string do
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, PuppyLog.Accounts.User do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_endpoint, [:endpoint]
  end
end
