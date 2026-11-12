defmodule PuppyLog.Daily.Routine do
  @moduledoc """
  A recurring part of the puppy's day: a fixed time or a time window on
  selected weekdays, optionally assigned to a household member.
  """

  use Ash.Resource,
    otp_app: :puppy_log,
    domain: PuppyLog.Daily,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  @kinds [:potty, :meal, :walk, :sleep, :play, :training, :manual]
  @fields [
    :name,
    :kind,
    :starts_at,
    :ends_at,
    :weekdays,
    :assignee_id,
    :remind?,
    :follow_up_minutes
  ]

  sqlite do
    table "routines"
    repo PuppyLog.Repo

    references do
      reference :created_by, on_delete: :nilify
      reference :assignee, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    read :active do
      description "Routines that are not archived, ordered by start time."
      filter expr(is_nil(archived_at))
      prepare build(sort: [starts_at: :asc, inserted_at: :asc])
    end

    create :create do
      primary? true
      accept @fields
      change relate_actor(:created_by)
    end

    update :update do
      primary? true
      accept @fields
      require_atomic? false
    end

    update :archive do
      accept []
      require_atomic? false
      change set_attribute(:archived_at, &DateTime.utc_now/0)
    end
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end
  end

  pub_sub do
    module PuppyLogWeb.Endpoint
    prefix "routines"

    publish_all :create, "changed"
    publish_all :update, "changed"
  end

  validations do
    validate compare(:ends_at, greater_than: :starts_at) do
      message "muss nach dem Beginn liegen"
      where present(:ends_at)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 60, trim?: true
    end

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: @kinds
    end

    attribute :starts_at, :time do
      allow_nil? false
      public? true
    end

    attribute :ends_at, :time do
      description "Nil for a fixed time, otherwise the end of the window"
      public? true
    end

    attribute :weekdays, {:array, :integer} do
      description "1 = Monday ... 7 = Sunday"
      allow_nil? false
      public? true
      default [1, 2, 3, 4, 5, 6, 7]
      constraints items: [min: 1, max: 7], min_length: 1
    end

    attribute :remind?, :boolean do
      allow_nil? false
      public? true
      default true
    end

    attribute :follow_up_minutes, :integer do
      public? true
      constraints min: 5, max: 240
    end

    attribute :archived_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :assignee, PuppyLog.Accounts.User do
      public? true
      allow_nil? true
    end

    belongs_to :created_by, PuppyLog.Accounts.User do
      public? true
      allow_nil? true
    end
  end
end
