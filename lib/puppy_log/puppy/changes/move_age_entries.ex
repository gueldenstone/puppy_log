defmodule PuppyLog.Puppy.Changes.MoveAgeEntries do
  @moduledoc """
  After the birth date changed, recomputes the due date of every open health
  entry that is due at an age. Removing the birth date leaves the dates as they are.
  """

  use Ash.Resource.Change

  require Ash.Query

  alias PuppyLog.Puppy.HealthEntry

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn changeset, profile ->
      if Ash.Changeset.changing_attribute?(changeset, :birth_date) and profile.birth_date do
        move_entries(changeset, profile)
      else
        {:ok, profile}
      end
    end)
  end

  defp move_entries(changeset, profile) do
    actor = changeset.context.private[:actor]

    HealthEntry
    |> Ash.Query.filter(status == :open and not is_nil(due_age))
    |> Ash.read!(authorize?: false)
    |> Enum.reduce_while({:ok, profile}, fn entry, acc ->
      entry
      |> Ash.Changeset.for_update(:follow_birth_date, %{}, actor: actor, authorize?: false)
      |> Ash.update()
      |> case do
        {:ok, _} -> {:cont, acc}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
