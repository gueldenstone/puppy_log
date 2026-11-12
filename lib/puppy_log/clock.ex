defmodule PuppyLog.Clock do
  @moduledoc """
  Local time for the household (Europe/Berlin by default).

  Use this instead of `Date.utc_today/0` so that an entry made shortly after
  midnight lands on the right day.

  Tests can pin the current time with `config :puppy_log, :clock_now,
  {module, function}` (set via `Application.put_env/3`, never in config
  files); the function returns a `DateTime` in any time zone.
  """

  @spec time_zone() :: String.t()
  def time_zone, do: Application.get_env(:puppy_log, :time_zone, "Europe/Berlin")

  @spec now() :: DateTime.t()
  def now do
    case Application.get_env(:puppy_log, :clock_now) do
      {module, function} -> module |> apply(function, []) |> local()
      nil -> DateTime.now!(time_zone())
    end
  end

  @doc "`now/0` in UTC, for timestamps that must follow the household clock."
  @spec utc_now() :: DateTime.t()
  def utc_now, do: now() |> DateTime.shift_zone!("Etc/UTC")

  @spec today() :: Date.t()
  def today, do: now() |> DateTime.to_date()

  @doc "Converts a (UTC) datetime to local time."
  @spec local(DateTime.t()) :: DateTime.t()
  def local(%DateTime{} = datetime), do: DateTime.shift_zone!(datetime, time_zone())

  @doc """
  The local wall-clock `time` on `date`.

  A time in the spring-forward gap becomes the later valid time (02:30 →
  03:30), an ambiguous time in autumn resolves to the first occurrence.
  """
  @spec local_datetime(Date.t(), Time.t()) :: DateTime.t()
  def local_datetime(%Date{} = date, %Time{} = time) do
    case DateTime.new(date, time, time_zone()) do
      {:ok, datetime} ->
        datetime

      {:ambiguous, first, _second} ->
        first

      {:gap, before_gap, _after_gap} ->
        # Interpret the wall time with the offset in force before the gap.
        offset = before_gap.utc_offset + before_gap.std_offset

        date
        |> NaiveDateTime.new!(time)
        |> NaiveDateTime.add(-offset, :second)
        |> DateTime.from_naive!("Etc/UTC")
        |> local()
    end
  end

  @doc "UTC bounds of the local day: start inclusive, next day's start exclusive."
  @spec day_bounds(Date.t()) :: {DateTime.t(), DateTime.t()}
  def day_bounds(%Date{} = date) do
    {utc_midnight(date), utc_midnight(Date.add(date, 1))}
  end

  defp utc_midnight(date) do
    date |> local_datetime(~T[00:00:00]) |> DateTime.shift_zone!("Etc/UTC")
  end
end
