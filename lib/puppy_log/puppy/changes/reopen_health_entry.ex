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
    changeset
    |> Ash.Changeset.force_change_attributes(%{status: :open, done_on: nil, batch: nil})
    |> Ash.Changeset.after_action(&remove_untouched_successor/2)
  end

  defp remove_untouched_successor(changeset, entry) do
    resource = entry.__struct__
    opts = [actor: changeset.context.private[:actor], authorize?: false]

    resource
    |> Ash.Query.filter(previous_id == ^entry.id and status == :open)
    |> Ash.read!(opts)
    |> Enum.filter(&(DateTime.compare(&1.updated_at, &1.inserted_at) == :eq))
    |> Enum.each(&Ash.destroy!(&1, opts))

    {:ok, entry}
  end
end
