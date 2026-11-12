defmodule PuppyLog.Clock do
  @moduledoc """
  Local time for the household (Europe/Berlin by default).

  Use this instead of `Date.utc_today/0` so that an entry made shortly after
  midnight lands on the right day.
  """

  @spec time_zone() :: String.t()
  def time_zone, do: Application.get_env(:puppy_log, :time_zone, "Europe/Berlin")

  @spec now() :: DateTime.t()
  def now, do: DateTime.now!(time_zone())

  @spec today() :: Date.t()
  def today, do: now() |> DateTime.to_date()

  @doc "Converts a (UTC) datetime to local time."
  @spec local(DateTime.t()) :: DateTime.t()
  def local(%DateTime{} = datetime), do: DateTime.shift_zone!(datetime, time_zone())
end
