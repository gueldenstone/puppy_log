defmodule PuppyLog.Daily.Changes.CompleteOccurrence do
  @moduledoc """
  Ticks off (`status: :done`, the default) or skips (`status: :skipped`) an
  open occurrence.

  Only an occurrence that is still open in the database can change: the
  update carries the filter `status == :open`, so it becomes
  `UPDATE ... WHERE id = ? AND status = 'open'`. SQLite serialises writes, so
  when two sessions tick the same occurrence at once exactly one UPDATE hits
  the row; the other matches no row, which Ash reports as a stale record.
  That error is turned into „Schon erledigt“.
  """

  use Ash.Resource.Change

  require Ash.Expr

  alias Ash.Error.Changes.{InvalidAttribute, StaleRecord}
  alias PuppyLog.Clock
  alias PuppyLog.Daily.Matching

  @already_done "Schon erledigt"

  @impl true
  def init(opts), do: {:ok, Keyword.put_new(opts, :status, :done)}

  @impl true
  def change(changeset, opts, _context) do
    changeset
    |> only_open()
    |> set_outcome(opts[:status])
  end

  defp only_open(changeset) do
    changeset
    |> Ash.Changeset.filter(Ash.Expr.expr(status == :open))
    |> Ash.Changeset.after_transaction(&already_done/2)
  end

  defp set_outcome(changeset, :skipped),
    do: Ash.Changeset.force_change_attribute(changeset, :status, :skipped)

  defp set_outcome(changeset, :done) do
    done_at = Ash.Changeset.get_argument(changeset, :done_at)
    occurrence = changeset.data

    changeset
    |> Ash.Changeset.force_change_attributes(%{
      status: :done,
      done_at: done_at,
      deviation_minutes: deviation(occurrence, done_at),
      event_id: Ash.Changeset.get_argument(changeset, :event_id)
    })
  end

  defp deviation(_occurrence, nil), do: nil

  defp deviation(occurrence, done_at) do
    Matching.deviation_minutes(
      occurrence.date,
      occurrence.planned_start,
      occurrence.planned_end,
      done_at |> Clock.local() |> DateTime.to_naive()
    )
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
