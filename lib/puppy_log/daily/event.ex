defmodule PuppyLog.Daily.Event do
  @moduledoc """
  Something that happened with the puppy: a potty break, a meal, a walk, …

  Logging an event can fulfil a planned routine occurrence (see
  `PuppyLog.Daily.Changes.LinkRoutine`); the occurrence then points back to
  the event via its `event_id`.
  """

  use Ash.Resource,
    otp_app: :puppy_log,
    domain: PuppyLog.Daily,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  require Ash.Query

  alias PuppyLog.Clock
  alias PuppyLog.Daily.Changes.LinkRoutine

  @kinds [:potty, :meal, :walk, :sleep, :play, :vomit, :other]
  @fields [:kind, :occurred_at, :pee, :poo, :nothing, :location, :name, :note]

  @doc "All event kinds."
  def kinds, do: @kinds

  @doc false
  # Pee, poo, nothing and location only mean something for potty breaks.
  def ignore_potty_fields(changeset, _context) do
    if Ash.Changeset.get_attribute(changeset, :kind) == :potty do
      changeset
    else
      Ash.Changeset.force_change_attributes(changeset, %{
        pee: false,
        poo: false,
        nothing: false,
        location: nil
      })
    end
  end

  @doc false
  def validate_potty_result(changeset, _context) do
    if Enum.any?([:pee, :poo, :nothing], &Ash.Changeset.get_attribute(changeset, &1)) do
      :ok
    else
      {:error, field: :pee, message: "Bitte Pipi, Kaka oder nichts wählen"}
    end
  end

  @doc false
  def validate_nothing(changeset, _context) do
    get = &Ash.Changeset.get_attribute(changeset, &1)

    cond do
      not get.(:nothing) ->
        :ok

      get.(:pee) or get.(:poo) ->
        {:error, field: :nothing, message: "schließt Pipi und Kaka aus"}

      get.(:location) != :outside ->
        {:error, field: :location, message: "„Nichts“ geht nur draußen"}

      true ->
        :ok
    end
  end

  @doc false
  def filter_between(query, first, last) do
    {from, _} = Clock.day_bounds(first)
    {_, to} = Clock.day_bounds(last)
    Ash.Query.filter(query, occurred_at >= ^from and occurred_at < ^to)
  end

  sqlite do
    table "events"
    repo PuppyLog.Repo

    references do
      reference :created_by, on_delete: :nilify
    end

    custom_indexes do
      index [:occurred_at]
    end
  end

  actions do
    defaults [:read]

    read :on_date do
      description "Events of one local day, newest first."
      argument :date, :date, allow_nil?: false

      prepare fn query, _context ->
        date = Ash.Query.get_argument(query, :date)
        filter_between(query, date, date)
      end

      prepare build(sort: [occurred_at: :desc])
    end

    read :between do
      description "Events from the local day `first` through `last`, oldest first."
      argument :first, :date, allow_nil?: false
      argument :last, :date, allow_nil?: false

      prepare fn query, _context ->
        filter_between(
          query,
          Ash.Query.get_argument(query, :first),
          Ash.Query.get_argument(query, :last)
        )
      end

      prepare build(sort: [occurred_at: :asc])
    end

    create :log do
      primary? true
      accept @fields

      argument :routine, :string do
        description ~s{"auto" (default), "none" or the id of the occurrence to fulfil}
        default "auto"
      end

      change relate_actor(:created_by, allow_nil?: true)
      change LinkRoutine
    end

    update :update do
      primary? true
      accept @fields
      require_atomic? false

      argument :routine, :string do
        description ~s{"auto" (default), "none" or the id of the occurrence to fulfil}
        default "auto"
      end

      change LinkRoutine
    end

    destroy :destroy do
      primary? true
      require_atomic? false
      change LinkRoutine
    end
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end
  end

  pub_sub do
    module PuppyLogWeb.Endpoint
    prefix "events"

    publish_all :create, "changed"
    publish_all :update, "changed"
    publish_all :destroy, "changed"
  end

  changes do
    change &__MODULE__.ignore_potty_fields/2, on: [:create, :update]
  end

  validations do
    validate present(:location) do
      on [:create, :update]
      where attribute_equals(:kind, :potty)
      message "Bitte drinnen oder draußen wählen"
    end

    validate &__MODULE__.validate_potty_result/2 do
      on [:create, :update]
      where attribute_equals(:kind, :potty)
    end

    validate &__MODULE__.validate_nothing/2 do
      on [:create, :update]
      where attribute_equals(:kind, :potty)
    end

    validate present(:name) do
      on [:create, :update]
      where attribute_equals(:kind, :other)
      message "Bitte einen Namen eingeben"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom do
      allow_nil? false
      public? true
      constraints one_of: @kinds
    end

    attribute :occurred_at, :utc_datetime_usec do
      allow_nil? false
      public? true
      default &PuppyLog.Clock.utc_now/0
    end

    attribute :pee, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :poo, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :nothing, :boolean do
      description "Went outside for a potty break, but nothing happened"
      allow_nil? false
      public? true
      default false
    end

    attribute :location, :atom do
      public? true
      constraints one_of: [:outside, :inside]
    end

    attribute :name, :string do
      public? true
      constraints min_length: 1, max_length: 60, trim?: true
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

    has_one :occurrence, PuppyLog.Daily.Occurrence do
      public? true
      destination_attribute :event_id
    end
  end
end
