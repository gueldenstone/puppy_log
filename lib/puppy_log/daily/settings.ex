defmodule PuppyLog.Daily.Settings do
  @moduledoc """
  Household-wide settings for daily routines. There is exactly one row.
  """

  use Ash.Resource,
    otp_app: :puppy_log,
    domain: PuppyLog.Daily,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  sqlite do
    table "daily_settings"
    repo PuppyLog.Repo
  end

  actions do
    defaults [:read]

    create :save do
      accept [:quiet_hours_enabled, :quiet_from, :quiet_until]
      upsert? true
      upsert_identity :only_one
    end
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end
  end

  pub_sub do
    module PuppyLogWeb.Endpoint
    prefix "daily_settings"

    publish_all :create, "changed"
    publish_all :update, "changed"
  end

  attributes do
    uuid_primary_key :id

    # Constant column with a unique index, so a second row cannot exist.
    attribute :singleton, :boolean do
      default true
      allow_nil? false
      writable? false
    end

    attribute :quiet_hours_enabled, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :quiet_from, :time do
      allow_nil? false
      public? true
      default ~T[22:00:00]
    end

    attribute :quiet_until, :time do
      allow_nil? false
      public? true
      default ~T[06:30:00]
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :only_one, [:singleton]
  end
end
