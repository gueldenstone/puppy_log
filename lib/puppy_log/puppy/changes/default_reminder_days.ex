defmodule PuppyLog.Puppy.Changes.DefaultReminderDays do
  @moduledoc """
  Takes `remind_days_before` from the household setting when none was given.
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :remind_days_before) do
      nil ->
        days = PuppyLog.Daily.settings(authorize?: false).health_reminder_days
        Ash.Changeset.force_change_attribute(changeset, :remind_days_before, days)

      _given ->
        changeset
    end
  end
end
