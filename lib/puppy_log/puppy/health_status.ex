defmodule PuppyLog.Puppy.HealthStatus do
  @moduledoc """
  Derives the display state of a health entry from its due date and the current time.
  Pure: works on any map or struct with `kind`, `due_on`, `due_time`,
  `remind_days_before` and `status`.
  """

  alias PuppyLog.Clock

  @type state :: :open | :due_soon | :due_today | :overdue | :done

  @doc "The state of `entry` at `now` (evaluated in household local time)."
  @spec state(map(), DateTime.t()) :: state()
  def state(%{status: :done}, _now), do: :done

  def state(%{} = entry, %DateTime{} = now) do
    local = Clock.local(now)
    today = DateTime.to_date(local)

    case Date.compare(entry.due_on, today) do
      :lt -> :overdue
      :eq -> same_day_state(entry, local)
      :gt -> upcoming_state(entry, today)
    end
  end

  @doc "Calendar days from `today` until the entry is due (negative when past)."
  @spec days_until(map(), Date.t()) :: integer()
  def days_until(%{due_on: due_on}, %Date{} = today), do: Date.diff(due_on, today)

  defp same_day_state(%{kind: :vet_visit, due_on: due_on, due_time: %Time{} = time}, local) do
    case DateTime.compare(Clock.local_datetime(due_on, time), local) do
      :lt -> :overdue
      _ -> :due_today
    end
  end

  defp same_day_state(_entry, _local), do: :due_today

  defp upcoming_state(entry, today) do
    if days_until(entry, today) <= entry.remind_days_before, do: :due_soon, else: :open
  end
end
