defmodule PuppyLog.Puppy.HealthEntry do
  @moduledoc """
  A health to-do or appointment: vaccination, deworming, flea/tick treatment,
  other care (all dated care items) or a vet visit (with time, place, assignee).
  """

  use Ash.Resource,
    otp_app: :puppy_log,
    domain: PuppyLog.Puppy,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  @kinds [:vaccination, :deworming, :flea_tick, :other_care, :vet_visit]
  @care_kinds [:vaccination, :deworming, :flea_tick, :other_care]
  @fields [
    :kind,
    :title,
    :due_on,
    :due_time,
    :location,
    :assignee_id,
    :notes,
    :remind_days_before,
    :repeat_weeks,
    :batch
  ]

  @doc "All health entry kinds."
  def kinds, do: @kinds

  @doc "Kinds that are dated care items (everything but vet visits)."
  def care_kinds, do: @care_kinds

  @doc false
  def sort_overview(entries) do
    {done, open} = Enum.split_with(entries, &(&1.status == :done))

    open =
      Enum.sort(open, fn a, b ->
        case compare_due(a, b) do
          :lt -> true
          :gt -> false
          :eq -> DateTime.compare(a.inserted_at, b.inserted_at) != :gt
        end
      end)

    done =
      Enum.sort(done, fn a, b ->
        case Date.compare(a.done_on || a.due_on, b.done_on || b.due_on) do
          :gt -> true
          :lt -> false
          :eq -> DateTime.compare(a.inserted_at, b.inserted_at) != :gt
        end
      end)

    open ++ done
  end

  # Due date first, then time of day (entries without a time come first).
  defp compare_due(a, b) do
    with :eq <- Date.compare(a.due_on, b.due_on) do
      Time.compare(a.due_time || ~T[00:00:00], b.due_time || ~T[00:00:00])
    end
  end

  sqlite do
    table "health_entries"
    repo PuppyLog.Repo

    references do
      reference :created_by, on_delete: :nilify
      reference :assignee, on_delete: :nilify
      reference :previous, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    read :overview do
      description "Open entries by due date and time, then done entries newest first."

      prepare fn query, _context ->
        # Done entries sort by a different key than open ones, so order the (small) result in memory.
        Ash.Query.after_action(query, fn _query, entries -> {:ok, sort_overview(entries)} end)
      end
    end

    create :create do
      primary? true
      accept @fields
      change PuppyLog.Puppy.Changes.DefaultReminderDays
      change relate_actor(:created_by)
    end

    update :update do
      primary? true
      accept @fields
      require_atomic? false
    end
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end
  end

  pub_sub do
    module PuppyLogWeb.Endpoint
    prefix "health_entries"

    publish_all :create, "changed"
    publish_all :update, "changed"
    publish_all :destroy, "changed"
  end

  validations do
    validate present(:due_time) do
      message "Bitte eine Uhrzeit angeben"
      where attribute_equals(:kind, :vet_visit)
    end

    validate {PuppyLog.Puppy.Validations.OnlyFor,
              field: :due_time, kinds: [:vet_visit], message: "Nur für Tierarzttermine"}

    validate {PuppyLog.Puppy.Validations.OnlyFor,
              field: :location, kinds: [:vet_visit], message: "Nur für Tierarzttermine"}

    validate {PuppyLog.Puppy.Validations.OnlyFor,
              field: :assignee_id, kinds: [:vet_visit], message: "Nur für Tierarzttermine"}

    validate {PuppyLog.Puppy.Validations.OnlyFor,
              field: :repeat_weeks, kinds: @care_kinds, message: "Nur für Vorsorge"}

    validate {PuppyLog.Puppy.Validations.OnlyFor,
              field: :batch, kinds: [:vaccination], message: "Nur für Impfungen"}
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: @kinds
    end

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints min_length: 1, max_length: 80, trim?: true
    end

    attribute :due_on, :date do
      allow_nil? false
      public? true
    end

    attribute :due_time, :time do
      description "Vet visits only"
      public? true
    end

    attribute :location, :string do
      description "Vet visits only"
      public? true
      constraints max_length: 120, trim?: true
    end

    attribute :notes, :string do
      public? true
      constraints max_length: 1000, trim?: true
    end

    attribute :remind_days_before, :integer do
      allow_nil? false
      public? true
      constraints min: 0, max: 14
    end

    attribute :repeat_weeks, :integer do
      description "Care kinds only; nil means no repetition"
      public? true
      constraints min: 1, max: 104
    end

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :open
      constraints one_of: [:open, :done]
    end

    attribute :done_on, :date, public?: true

    attribute :batch, :string do
      description "Vaccinations only"
      public? true
      constraints max_length: 120, trim?: true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :assignee, PuppyLog.Accounts.User do
      public? true
      allow_nil? true
    end

    belongs_to :previous, __MODULE__ do
      public? true
      allow_nil? true
    end

    belongs_to :created_by, PuppyLog.Accounts.User do
      public? true
      allow_nil? true
    end
  end
end
