defmodule PuppyLog.Daily.Occurrence do
  @moduledoc """
  A routine planned on one day. Keeps a snapshot of the routine (name, kind,
  planned time, assignee, reminder settings) so history does not change when
  the routine is edited later, plus the outcome: done, skipped or still open.
  """

  use Ash.Resource,
    otp_app: :puppy_log,
    domain: PuppyLog.Daily,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias PuppyLog.Daily.Changes.CompleteOccurrence
  alias PuppyLog.Daily.Notify

  @snapshot [
    :name,
    :kind,
    :planned_start,
    :planned_end,
    :assignee_id,
    :remind?,
    :follow_up_minutes
  ]

  sqlite do
    table "occurrences"
    repo PuppyLog.Repo

    references do
      reference :routine, on_delete: :delete
      reference :assignee, on_delete: :nilify
      reference :completed_by, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    read :on_date do
      argument :date, :date, allow_nil?: false
      filter expr(date == ^arg(:date))
      prepare build(sort: [planned_start: :asc, name: :asc])
    end

    create :plan do
      description "Internal: plans a routine on a day. Existing occurrences stay untouched."
      accept [:routine_id, :date | @snapshot]
      upsert? true
      upsert_identity :one_per_day
      upsert_fields []
    end

    update :replan do
      description "Internal: refreshes the snapshot of an open occurrence after a routine edit."
      accept @snapshot
    end

    update :complete do
      require_atomic? false
      argument :done_at, :utc_datetime_usec, allow_nil?: false
      argument :event_id, :uuid
      change CompleteOccurrence
      change relate_actor(:completed_by, allow_nil?: true)
      change after_transaction(&notify_outcome/3)
    end

    update :skip do
      require_atomic? false
      change {CompleteOccurrence, status: :skipped}
      change relate_actor(:completed_by, allow_nil?: true)
      change after_transaction(&notify_outcome/3)
    end

    update :mark_reminded do
      description """
      Internal: records that the reminder goes out. Run as a bulk update over
      `reminded_at == nil`, so a reminder is claimed (and sent) only once.
      """

      argument :at, :utc_datetime_usec, allow_nil?: false
      change set_attribute(:reminded_at, arg(:at))
    end

    update :mark_follow_up_sent do
      description "Internal: like `:mark_reminded`, for the follow-up."
      argument :at, :utc_datetime_usec, allow_nil?: false
      change set_attribute(:follow_up_sent_at, arg(:at))
    end

    update :attach_event do
      description """
      Internal: links (or, with nil, unlinks) an event to an occurrence that was
      already ticked off by hand. The recorded outcome stays as it is.
      """

      argument :event_id, :uuid
      change set_attribute(:event_id, arg(:event_id))
    end

    update :reopen do
      accept []
      change set_attribute(:status, :open)
      change set_attribute(:done_at, nil)
      change set_attribute(:deviation_minutes, nil)
      change set_attribute(:completed_by_id, nil)
      change set_attribute(:event_id, nil)
    end
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end
  end

  pub_sub do
    module PuppyLogWeb.Endpoint
    prefix "occurrences"

    publish_all :create, "changed"
    publish_all :update, "changed"
    publish_all :destroy, "changed"
  end

  attributes do
    uuid_primary_key :id

    attribute :date, :date do
      allow_nil? false
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: PuppyLog.Daily.Routine.kinds()
    end

    attribute :planned_start, :time do
      allow_nil? false
      public? true
    end

    attribute :planned_end, :time, public?: true

    attribute :remind?, :boolean do
      allow_nil? false
      public? true
      default true
    end

    attribute :follow_up_minutes, :integer, public?: true

    attribute :status, :atom do
      allow_nil? false
      public? true
      default :open
      constraints one_of: [:open, :done, :skipped]
    end

    attribute :done_at, :utc_datetime_usec, public?: true

    attribute :deviation_minutes, :integer do
      description "Minutes early (negative) or late (positive) relative to the plan"
      public? true
    end

    attribute :event_id, :uuid do
      description "The event that fulfilled this occurrence (no database reference)"
      public? true
    end

    attribute :reminded_at, :utc_datetime_usec, public?: true
    attribute :follow_up_sent_at, :utc_datetime_usec, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :routine, PuppyLog.Daily.Routine do
      public? true
      allow_nil? false
    end

    belongs_to :assignee, PuppyLog.Accounts.User do
      public? true
      allow_nil? true
    end

    belongs_to :completed_by, PuppyLog.Accounts.User do
      public? true
      allow_nil? true
    end
  end

  identities do
    identity :one_per_day, [:routine_id, :date]
  end

  @doc false
  def notify_outcome(_changeset, {:ok, occurrence} = result, context) do
    Notify.after_outcome(occurrence, context.actor)
    result
  end

  def notify_outcome(_changeset, result, _context), do: result
end
