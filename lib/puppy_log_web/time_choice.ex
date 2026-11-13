defmodule PuppyLogWeb.TimeChoice do
  @moduledoc """
  The quick time choice of the tick-off and log sheets: „Jetzt“, a few
  minutes ago, or an exact local time (a `datetime-local` value in the
  household time zone).
  """

  alias PuppyLog.Clock

  @minutes_ago ~w(15 20 30)

  @doc "Labels and values of the choices, in display order."
  @spec options() :: [{String.t(), String.t()}]
  def options do
    [{"Jetzt", "now"}] ++
      Enum.map(@minutes_ago, &{"vor #{&1} Min", &1}) ++
      [{"Uhrzeit", "custom"}]
  end

  @doc """
  The point in time of a choice. `custom` is only used for `"custom"`; times
  in the future (after `now`) are rejected.
  """
  @spec resolve(String.t(), String.t() | nil, DateTime.t()) :: {:ok, DateTime.t()} | :error
  def resolve("now", _custom, now), do: {:ok, now}

  def resolve(minutes, _custom, now) when minutes in @minutes_ago,
    do: {:ok, DateTime.add(now, -String.to_integer(minutes) * 60, :second)}

  def resolve("custom", custom, now) when is_binary(custom) do
    with {:ok, naive} <- parse_local(custom),
         at = Clock.local_datetime(NaiveDateTime.to_date(naive), NaiveDateTime.to_time(naive)),
         false <- DateTime.after?(at, now) do
      {:ok, at}
    else
      _ -> :error
    end
  end

  def resolve(_choice, _custom, _now), do: :error

  @doc "A local datetime as the value of a `datetime-local` input (minutes)."
  @spec to_input(DateTime.t()) :: String.t()
  def to_input(%DateTime{} = datetime) do
    datetime |> Clock.local() |> Calendar.strftime("%Y-%m-%dT%H:%M")
  end

  # "2026-11-12T09:05" (browsers may add seconds)
  defp parse_local(<<_::binary-size(16)>> = value), do: NaiveDateTime.from_iso8601(value <> ":00")
  defp parse_local(value), do: NaiveDateTime.from_iso8601(value)
end
