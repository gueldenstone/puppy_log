defmodule PuppyLog.Puppy.WeightEntry do
  @moduledoc """
  A weighing. Stored in grams to avoid rounding issues; the UI works in kg.
  """

  use Ash.Resource,
    otp_app: :puppy_log,
    domain: PuppyLog.Puppy,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  sqlite do
    table "weight_entries"
    repo PuppyLog.Repo

    references do
      reference :created_by, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    read :history do
      description "All weighings, newest first."
      prepare build(sort: [measured_on: :desc, inserted_at: :desc])

      pagination offset?: true, keyset?: true, required?: false, default_limit: 50
    end

    create :create do
      primary? true
      accept [:measured_on, :weight_grams, :note]

      argument :weight_kg, :string do
        description "Weight as typed by a person, e.g. \"4,35\". Overrides weight_grams."
      end

      change PuppyLog.Puppy.Changes.ParseWeightKg
      change relate_actor(:created_by)
    end

    update :update do
      primary? true
      accept [:measured_on, :weight_grams, :note]
      require_atomic? false

      argument :weight_kg, :string

      change PuppyLog.Puppy.Changes.ParseWeightKg
    end
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end
  end

  pub_sub do
    module PuppyLogWeb.Endpoint
    prefix "weight_entries"

    publish_all :create, "changed"
    publish_all :update, "changed"
    publish_all :destroy, "changed"
  end

  validations do
    validate compare(:measured_on, less_than_or_equal_to: &PuppyLog.Clock.today/0) do
      message "darf nicht in der Zukunft liegen"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :measured_on, :date do
      allow_nil? false
      public? true
      default &PuppyLog.Clock.today/0
    end

    attribute :weight_grams, :integer do
      allow_nil? false
      public? true
      constraints min: 50, max: 120_000
    end

    attribute :note, :string do
      public? true
      constraints max_length: 500, trim?: true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :created_by, PuppyLog.Accounts.User do
      public? true
      allow_nil? true
    end
  end
end
