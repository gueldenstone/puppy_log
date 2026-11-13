defmodule PuppyLogWeb.RoutineActions do
  @moduledoc """
  The row events of `PuppyLogWeb.RoutineRow` (`"complete"`, `"skip"`,
  `"reopen"`), shared by the day lists „Heute“ and the day view in „Verlauf“.
  """

  alias PuppyLog.{Clock, Daily}
  alias PuppyLogWeb.RoutineSheet

  @load [:completed_by, :assignee]

  @doc "What a routine row and the sheet need loaded on an occurrence."
  def load, do: @load

  @doc """
  Runs the row event on the occurrence `id`. Returns the updated occurrence
  (with `load/0`) or a German error message.
  """
  @spec run(String.t(), String.t(), struct) :: {:ok, struct} | {:error, String.t()}
  def run(event, id, actor) when event in ~w(complete skip reopen) do
    opts = [actor: actor]

    with {:ok, occurrence} <- Daily.get_occurrence(id, opts),
         {:ok, updated} <- action(event, occurrence, opts) do
      {:ok, Ash.load!(updated, @load, opts)}
    else
      {:error, error} -> {:error, RoutineSheet.error_message(error)}
    end
  end

  defp action("complete", occurrence, opts),
    do: Daily.complete_occurrence(occurrence, %{done_at: Clock.utc_now()}, opts)

  defp action("skip", occurrence, opts), do: Daily.skip_occurrence(occurrence, opts)
  defp action("reopen", occurrence, opts), do: Daily.reopen_occurrence(occurrence, opts)
end
