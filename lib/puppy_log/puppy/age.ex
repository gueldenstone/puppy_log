defmodule PuppyLog.Puppy.Age do
  @moduledoc """
  Human readable puppy age in German.
  """

  @doc """
  Full weeks since birth.

      iex> PuppyLog.Puppy.Age.weeks(~D[2026-08-06], ~D[2026-11-12])
      14
  """
  @spec weeks(Date.t(), Date.t()) :: non_neg_integer()
  def weeks(birth_date, today), do: max(div(Date.diff(today, birth_date), 7), 0)

  @doc """
  Weeks up to 16 weeks, then months, then years.

      iex> PuppyLog.Puppy.Age.describe(~D[2026-08-06], ~D[2026-11-12])
      "14 Wochen"
      iex> PuppyLog.Puppy.Age.describe(~D[2026-11-10], ~D[2026-11-12])
      "2 Tage"
      iex> PuppyLog.Puppy.Age.describe(~D[2026-01-15], ~D[2026-11-12])
      "9 Monate"
      iex> PuppyLog.Puppy.Age.describe(~D[2023-05-01], ~D[2026-11-12])
      "3 Jahre"
  """
  @spec describe(Date.t() | nil, Date.t()) :: String.t() | nil
  def describe(nil, _today), do: nil

  def describe(birth_date, today) do
    days = Date.diff(today, birth_date)
    weeks = div(days, 7)
    months = months(birth_date, today)

    cond do
      days < 14 -> plural(days, "Tag", "Tage")
      weeks <= 16 -> plural(weeks, "Woche", "Wochen")
      months < 24 -> plural(months, "Monat", "Monate")
      true -> plural(div(months, 12), "Jahr", "Jahre")
    end
  end

  defp months(birth_date, today) do
    months = (today.year - birth_date.year) * 12 + today.month - birth_date.month
    if today.day < birth_date.day, do: months - 1, else: months
  end

  defp plural(1, singular, _plural), do: "1 #{singular}"
  defp plural(n, _singular, plural), do: "#{n} #{plural}"
end
