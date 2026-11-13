defmodule PuppyLog.Puppy.Changes.CompleteHealthEntry do
  @moduledoc """
  Completes a health entry and, when it repeats, creates the next one.

  Used by `:complete` (open entry -> done) and by `:create` with `status: :done`
  (past entries entered directly as done). The completion date must not lie in
  the future.

  For `:complete` only an entry that is still open in the database can change:
  the update carries the filter `status == :open` (see
  `PuppyLog.Daily.Changes.CompleteOccurrence`), so of two concurrent completions
  exactly one UPDATE hits the row and only that one creates the successor. The
  stale-record error of the loser becomes „Schon erledigt“.

  The successor (same kind, title, notes, lead time and repetition, due
  `repeat_weeks` weeks after the completion date) is created in the same
  transaction, owned by the acting user.
  """

  use Ash.Resource.Change

  require Ash.Expr

  alias Ash.Error.Changes.{InvalidAttribute, StaleRecord}
  alias PuppyLog.Clock

  @already_done "Schon erledigt"

  @impl true
  def change(changeset, _opts, _context) do
    if changeset.action.type == :update, do: complete(changeset), else: entered_as_done(changeset)
  end

  defp complete(changeset) do
    done_on = Ash.Changeset.get_argument(changeset, :done_on) || Clock.today()

    changeset
    |> Ash.Changeset.filter(Ash.Expr.expr(status == :open))
    |> Ash.Changeset.after_transaction(&already_done/2)
    |> Ash.Changeset.force_change_attributes(%{
      status: :done,
      done_on: done_on,
      batch: Ash.Changeset.get_argument(changeset, :batch)
    })
    |> not_in_future(done_on)
    |> Ash.Changeset.after_action(&create_successor/2)
  end

  defp entered_as_done(changeset) do
    if Ash.Changeset.get_attribute(changeset, :status) == :done do
      done_on = Ash.Changeset.get_attribute(changeset, :done_on) || Clock.today()

      changeset
      |> Ash.Changeset.force_change_attribute(:done_on, done_on)
      |> not_in_future(done_on)
      |> Ash.Changeset.after_action(&create_successor/2)
    else
      changeset
    end
  end

  defp not_in_future(changeset, done_on) do
    if Date.after?(done_on, Clock.today()) do
      Ash.Changeset.add_error(changeset,
        field: :done_on,
        message: "Darf nicht in der Zukunft liegen"
      )
    else
      changeset
    end
  end

  defp create_successor(_changeset, %{repeat_weeks: nil} = entry), do: {:ok, entry}

  defp create_successor(changeset, %{repeat_weeks: weeks} = entry) do
    attrs = %{
      kind: entry.kind,
      title: entry.title,
      notes: entry.notes,
      remind_days_before: entry.remind_days_before,
      repeat_weeks: weeks,
      due_on: Date.add(entry.done_on, 7 * weeks)
    }

    entry.__struct__
    |> Ash.Changeset.for_create(:create, attrs,
      actor: changeset.context.private[:actor],
      authorize?: false
    )
    |> Ash.Changeset.force_change_attribute(:previous_id, entry.id)
    |> Ash.create()
    |> case do
      {:ok, _successor} -> {:ok, entry}
      {:error, error} -> {:error, error}
    end
  end

  defp already_done(_changeset, {:error, error} = result) do
    if stale?(error) do
      {:error, InvalidAttribute.exception(field: :status, message: @already_done)}
    else
      result
    end
  end

  defp already_done(_changeset, result), do: result

  defp stale?(%StaleRecord{}), do: true
  defp stale?(%{errors: errors}) when is_list(errors), do: Enum.any?(errors, &stale?/1)
  defp stale?(_error), do: false
end
