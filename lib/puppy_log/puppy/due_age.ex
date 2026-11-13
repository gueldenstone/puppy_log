defmodule PuppyLog.Puppy.DueAge do
  @moduledoc """
  A health entry can be due "at an age" (e.g. 8 weeks) instead of on a fixed
  date. This module turns an age into a date and a label.
  """

  @type unit :: :weeks | :months

  @doc "Allowed ages per unit."
  @spec ranges() :: %{weeks: Range.t(), months: Range.t()}
  def ranges, do: %{weeks: 1..104, months: 1..36}

  @doc "The date on which a puppy born on `birth_date` is `n` weeks or months old."
  @spec due_on(Date.t(), pos_integer(), unit()) :: Date.t()
  def due_on(birth_date, n, :weeks), do: Date.add(birth_date, 7 * n)
  def due_on(birth_date, n, :months), do: Date.shift(birth_date, month: n)

  @doc "German label, e.g. „mit 8 Wochen“."
  @spec label(pos_integer(), unit()) :: String.t()
  def label(1, :weeks), do: "mit 1 Woche"
  def label(n, :weeks), do: "mit #{n} Wochen"
  def label(1, :months), do: "mit 1 Monat"
  def label(n, :months), do: "mit #{n} Monaten"
end
