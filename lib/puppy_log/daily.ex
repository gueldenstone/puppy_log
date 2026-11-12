defmodule PuppyLog.Daily do
  @moduledoc """
  Everyday life with the puppy: routines, household settings, planned occurrences (and
  later events).
  """

  use Ash.Domain, otp_app: :puppy_log, extensions: [AshAdmin.Domain]

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

    resource PuppyLog.Daily.Settings do
      define :list_settings, action: :read
      define :save_settings, action: :save
    end
  end
end
