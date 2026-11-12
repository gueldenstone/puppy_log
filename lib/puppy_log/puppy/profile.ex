defmodule PuppyLog.Puppy.Profile do
  @moduledoc """
  The puppy's profile. There is exactly one (enforced by a unique constant).
  """

  use Ash.Resource,
    otp_app: :puppy_log,
    domain: PuppyLog.Puppy,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  sqlite do
    table "puppy_profiles"
    repo PuppyLog.Repo

    references do
      reference :created_by, on_delete: :nilify
      reference :updated_by, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    read :current do
      description "The one puppy profile, or nothing if it was not set up yet."
      get? true
    end

    create :create do
      accept [:name, :birth_date, :breed, :chip_number, :photo_path]
      change PuppyLog.Puppy.Changes.NormalizeChipNumber
      change relate_actor(:created_by)
      change relate_actor(:updated_by)
    end

    update :update do
      accept [:name, :birth_date, :breed, :chip_number, :photo_path]
      require_atomic? false
      change PuppyLog.Puppy.Changes.NormalizeChipNumber
      change relate_actor(:updated_by)
    end
  end

  policies do
    # One household: every member may do everything.
    policy always() do
      authorize_if actor_present()
    end
  end

  pub_sub do
    module PuppyLogWeb.Endpoint
    prefix "puppy_profile"

    publish_all :create, "changed"
    publish_all :update, "changed"
  end

  validations do
    validate match(:chip_number, ~r/\A\d{15}\z/) do
      message "muss aus 15 Ziffern bestehen"
      where present(:chip_number)
    end

    validate compare(:birth_date, less_than_or_equal_to: &PuppyLog.Clock.today/0) do
      message "darf nicht in der Zukunft liegen"
      where present(:birth_date)
    end
  end

  attributes do
    uuid_primary_key :id

    # Constant column with a unique index, so a second profile cannot exist.
    attribute :singleton, :boolean do
      default true
      allow_nil? false
      writable? false
    end

    attribute :name, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 60, trim?: true
    end

    attribute :birth_date, :date, public?: true

    attribute :breed, :string do
      public? true
      constraints max_length: 80, trim?: true
    end

    attribute :chip_number, :string do
      description "Transponder number (ISO 11784, 15 digits)"
      public? true
      constraints trim?: true
    end

    attribute :photo_path, :string do
      description "File name inside the uploads directory"
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :created_by, PuppyLog.Accounts.User, public?: true
    belongs_to :updated_by, PuppyLog.Accounts.User, public?: true
  end

  identities do
    identity :only_one, [:singleton]
  end
end
