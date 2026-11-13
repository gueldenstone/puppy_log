defmodule PuppyLog.Daily do
  @moduledoc """
  Everyday life with the puppy: routines, household settings, planned occurrences and
  the events that fulfil them.
  """

  use Ash.Domain, otp_app: :puppy_log, extensions: [AshAdmin.Domain]

  require Ash.Query

  alias PuppyLog.Daily.Changes.LinkRoutine

  admin do
    show? true
  end

  @doc """
  The household settings: the stored singleton, or an unsaved struct with defaults.
  """
  def settings(opts) do
    case list_settings!(opts) do
      [settings | _] -> settings
      [] -> %PuppyLog.Daily.Settings{}
    end
  end

  @doc "Plans all routines due on `date` (internal, `authorize?: false`). Idempotent."
  defdelegate ensure_day(date, opts \\ []), to: PuppyLog.Daily.Planner

  @doc "Plans `first..last`, clipped to `arrival_date..today` (internal). Idempotent."
  defdelegate ensure_days(first, last, opts \\ []), to: PuppyLog.Daily.Planner

  @doc """
  Read-only helper for the event form: the occurrence an event with `kind`,
  `location` and `occurred_at` would fulfil automatically (`auto`, or `nil`)
  and all candidates of its local day, closest first. Plans that day first.
  Pass `event_id` when editing an event so its own occurrence counts as free.
  """
  def match_preview(%{kind: kind, location: location, occurred_at: occurred_at} = input, opts) do
    local = PuppyLog.Clock.local(occurred_at)
    date = DateTime.to_date(local)
    :ok = ensure_day(date)

    date
    |> list_occurrences_on!(opts)
    |> LinkRoutine.choices(
      %{kind: kind, location: location},
      DateTime.to_naive(local),
      Map.get(input, :event_id)
    )
  end

  @doc "Up to 5 distinct names of the latest `:other` events, latest first."
  def recent_other_names(opts) do
    PuppyLog.Daily.Event
    |> Ash.Query.filter(kind == :other and not is_nil(name))
    |> Ash.Query.sort(occurred_at: :desc)
    |> Ash.Query.select([:name])
    |> Ash.Query.limit(50)
    |> Ash.read!(opts)
    |> Enum.map(& &1.name)
    |> Enum.uniq()
    |> Enum.take(5)
  end

  resources do
    resource PuppyLog.Daily.Routine do
      define :list_routines, action: :active
      define :get_routine, action: :read, get_by: [:id]
      define :create_routine, action: :create
      define :update_routine, action: :update
      define :archive_routine, action: :archive
    end

    resource PuppyLog.Daily.Occurrence do
      define :list_occurrences_on, action: :on_date, args: [:date]
      define :get_occurrence, action: :read, get_by: [:id]
      define :complete_occurrence, action: :complete
      define :skip_occurrence, action: :skip
      define :reopen_occurrence, action: :reopen
    end

    resource PuppyLog.Daily.Event do
      define :log_event, action: :log
      define :update_event, action: :update
      define :delete_event, action: :destroy
      define :list_events_on, action: :on_date, args: [:date]
      define :list_events_between, action: :between, args: [:first, :last]
      define :get_event, action: :read, get_by: [:id]
    end

    resource PuppyLog.Daily.Settings do
      define :list_settings, action: :read
      define :save_settings, action: :save
    end
  end
end
