defmodule PuppyLog.Puppy.Weight do
  @moduledoc """
  Converts between grams (storage) and German kg notation (UI): "4,35" ⇄ 4350.
  """

  @doc """
  Parses user input in kg. Accepts comma or dot as decimal separator and an
  optional "kg" suffix.

      iex> PuppyLog.Puppy.Weight.parse_kg("4,35")
      {:ok, 4350}
      iex> PuppyLog.Puppy.Weight.parse_kg("12.5 kg")
      {:ok, 12500}
      iex> PuppyLog.Puppy.Weight.parse_kg("viel")
      :error
  """
  @spec parse_kg(String.t() | nil) :: {:ok, non_neg_integer()} | :error
  def parse_kg(input) when is_binary(input) do
    normalized =
      input
      |> String.trim()
      |> String.replace(~r/\s*kg\z/i, "")
      |> String.replace(",", ".")

    case Decimal.parse(normalized) do
      {decimal, ""} ->
        grams = decimal |> Decimal.mult(1000) |> Decimal.round(0) |> Decimal.to_integer()
        if grams > 0, do: {:ok, grams}, else: :error

      _ ->
        :error
    end
  end

  def parse_kg(_), do: :error

  @doc """
  Formats grams as kg with German decimal comma, without unit.

      iex> PuppyLog.Puppy.Weight.to_kg_string(4350)
      "4,35"
      iex> PuppyLog.Puppy.Weight.to_kg_string(12000)
      "12"
      iex> PuppyLog.Puppy.Weight.to_kg_string(12050)
      "12,05"
  """
  @spec to_kg_string(integer()) :: String.t()
  def to_kg_string(grams) when is_integer(grams) do
    kg = div(grams, 1000)

    case rem(abs(grams), 1000) do
      0 ->
        Integer.to_string(kg)

      rest ->
        "#{kg},#{rest |> Integer.to_string() |> String.pad_leading(3, "0") |> String.trim_trailing("0")}"
    end
  end

  @doc """
  Formats a weight difference, e.g. "+350 g" or "−1,2 kg".
  """
  @spec format_delta(integer()) :: String.t()
  def format_delta(0), do: "±0 g"

  def format_delta(grams) when abs(grams) < 1000 do
    sign(grams) <> "#{abs(grams)} g"
  end

  def format_delta(grams), do: sign(grams) <> to_kg_string(abs(grams)) <> " kg"

  defp sign(grams) when grams > 0, do: "+"
  defp sign(_grams), do: "−"
end
