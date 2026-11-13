defmodule PuppyLog.Puppy.Changes.ReopenHealthEntry do
  @moduledoc """
  Reopens a done health entry (clears completion date and batch) and deletes its
  successor, but only while that is still open and unchanged since it was
  created (`updated_at == inserted_at`).
  """

  use Ash.Resource.Change

  require Ash.Query

  @impl true
  def change(changeset, _opts, _context) do
    if changeset.data.status == :done do
      changeset
      |> Ash.Changeset.force_change_attributes(%{status: :open, done_on: nil, batch: nil})
      |> Ash.Changeset.after_action(&remove_untouched_successor/2)
    else
      Ash.Changeset.add_error(changeset, field: :status, message: "Ist noch offen")
    end
  end

  defp remove_untouched_successor(changeset, entry) do
    opts = [actor: changeset.context.private[:actor], authorize?: false]

    with {:ok, successors} <-
           entry.__struct__
           |> Ash.Query.filter(previous_id == ^entry.id and status == :open)
           |> Ash.read(opts),
         :ok <- destroy_untouched(successors, opts) do
      {:ok, entry}
    end
  end

  defp destroy_untouched(successors, opts) do
    successors
    |> Enum.filter(&(DateTime.compare(&1.updated_at, &1.inserted_at) == :eq))
    |> Enum.reduce_while(:ok, fn successor, :ok ->
      case Ash.destroy(successor, opts) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
end
