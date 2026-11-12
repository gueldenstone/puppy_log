defmodule PuppyLog.Daily do
  @moduledoc """
  Everyday life with the puppy: routines, household settings (and later
  occurrences and events).
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

  resources do
    resource PuppyLog.Daily.Routine do
      define :list_routines, action: :active
      define :get_routine, action: :read, get_by: [:id]
      define :create_routine, action: :create
      define :update_routine, action: :update
      define :archive_routine, action: :archive
    end

    resource PuppyLog.Daily.Settings do
      define :list_settings, action: :read
      define :save_settings, action: :save
    end
  end
end
