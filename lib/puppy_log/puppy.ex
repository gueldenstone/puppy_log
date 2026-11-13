defmodule PuppyLog.Puppy do
  @moduledoc """
  The puppy itself: profile, weight history and health entries.
  """

  use Ash.Domain, otp_app: :puppy_log, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  @doc """
  Latest weighing and the change since the one before.

  Returns `%{latest: entry | nil, previous: entry | nil, change_grams: integer | nil}`.
  """
  def weight_summary(opts) do
    case list_weights!(Keyword.put(opts, :query, limit: 2)) do
      [latest, previous] ->
        %{
          latest: latest,
          previous: previous,
          change_grams: latest.weight_grams - previous.weight_grams
        }

      [latest] ->
        %{latest: latest, previous: nil, change_grams: nil}

      [] ->
        %{latest: nil, previous: nil, change_grams: nil}
    end
  end

  resources do
    resource PuppyLog.Puppy.Profile do
      define :get_profile, action: :current, not_found_error?: false
      define :create_profile, action: :create
      define :update_profile, action: :update
    end

    resource PuppyLog.Puppy.WeightEntry do
      define :list_weights, action: :history
      define :get_weight, action: :read, get_by: [:id]
      define :add_weight, action: :create
      define :update_weight, action: :update
      define :delete_weight, action: :destroy
    end

    resource PuppyLog.Puppy.HealthEntry do
      define :list_health_entries, action: :overview
      define :get_health_entry, action: :read, get_by: [:id]
      define :create_health_entry, action: :create
      define :update_health_entry, action: :update
      define :complete_health_entry, action: :complete
      define :reopen_health_entry, action: :reopen
      define :delete_health_entry, action: :destroy
    end
  end
end
