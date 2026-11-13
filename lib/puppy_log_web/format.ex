defmodule PuppyLogWeb.Format do
  @moduledoc "German date formatting for the UI."

  @weekdays ~w(Mo Di Mi Do Fr Sa So)
  @months_short ~w(Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez)
  @months ~w(Januar Februar März April Mai Juni Juli August September Oktober November Dezember)

  @doc ~S"""
      iex> PuppyLogWeb.Format.short_date(~D[2026-11-12])
      "Do, 12. Nov"
  """
  def short_date(%Date{} = date),
    do: "#{weekday(date)}, #{date.day}. #{Enum.at(@months_short, date.month - 1)}"

  @doc ~S"""
      iex> PuppyLogWeb.Format.long_date(~D[2026-08-06])
      "6. August 2026"
  """
  def long_date(%Date{} = date),
    do: "#{date.day}. #{Enum.at(@months, date.month - 1)} #{date.year}"

  @doc ~S"""
  A span of days; the year only when it differs.

      iex> PuppyLogWeb.Format.date_range(~D[2026-11-06], ~D[2026-11-12])
      "6. Nov bis 12. Nov"
      iex> PuppyLogWeb.Format.date_range(~D[2025-11-13], ~D[2026-11-12])
      "13. Nov 2025 bis 12. Nov 2026"
  """
  def date_range(%Date{year: year} = first, %Date{year: year} = last),
    do: "#{day_month(first)} bis #{day_month(last)}"

  def date_range(%Date{} = first, %Date{} = last),
    do: "#{day_month(first)} #{first.year} bis #{day_month(last)} #{last.year}"

  defp day_month(date), do: "#{date.day}. #{Enum.at(@months_short, date.month - 1)}"

  @doc ~S"""
  Relative day for lists: "Heute", "Gestern", otherwise the short date.

      iex> PuppyLogWeb.Format.relative_day(~D[2026-11-11], ~D[2026-11-12])
      "Gestern"
  """
  def relative_day(%Date{} = date, %Date{} = today) do
    case Date.diff(today, date) do
      0 -> "Heute"
      1 -> "Gestern"
      _ -> short_date(date)
    end
  end

  @doc ~S"""
      iex> PuppyLogWeb.Format.month_short(~D[2026-11-19])
      "Nov"
  """
  def month_short(%Date{month: month}), do: Enum.at(@months_short, month - 1)

  @doc ~S"""
  Numeric day and month, with the year when it is not `today`'s.

      iex> PuppyLogWeb.Format.day_month_numeric(~D[2026-11-01], ~D[2026-11-13])
      "01.11."
      iex> PuppyLogWeb.Format.day_month_numeric(~D[2027-01-05], ~D[2026-11-13])
      "05.01.2027"
  """
  def day_month_numeric(%Date{year: year} = date, %Date{year: year}),
    do: Calendar.strftime(date, "%d.%m.")

  def day_month_numeric(%Date{} = date, %Date{}), do: Calendar.strftime(date, "%d.%m.%Y")

  def weekday(%Date{} = date), do: Enum.at(@weekdays, Date.day_of_week(date) - 1)

  @doc ~S"""
  Short German summary of routine weekdays (1 = Monday ... 7 = Sunday).

      iex> PuppyLogWeb.Format.weekdays([1, 2, 3, 4, 5, 6, 7])
      "täglich"
      iex> PuppyLogWeb.Format.weekdays([1, 2, 3, 4, 5])
      "Mo–Fr"
      iex> PuppyLogWeb.Format.weekdays([5, 1, 3])
      "Mo, Mi, Fr"
  """
  def weekdays(days) when is_list(days), do: days |> Enum.sort() |> Enum.uniq() |> summary()

  defp summary([1, 2, 3, 4, 5, 6, 7]), do: "täglich"
  defp summary([1, 2, 3, 4, 5]), do: "Mo–Fr"
  defp summary(days), do: Enum.map_join(days, ", ", &Enum.at(@weekdays, &1 - 1))

  @doc "Weekday abbreviations Mo ... So, in order."
  def weekday_names, do: @weekdays

  @doc ~S"""
  Groups a 15 digit chip number for reading: "276 098 106 543 210".

      iex> PuppyLogWeb.Format.chip_number("276098106543210")
      "276 098 106 543 210"
  """
  def chip_number(nil), do: nil

  def chip_number(number) do
    number |> String.graphemes() |> Enum.chunk_every(3) |> Enum.map_join(" ", &Enum.join/1)
  end

  @doc ~S"""
  A duration in minutes, in hours once it reaches an hour.

      iex> PuppyLogWeb.Format.duration(45)
      "45 Min"
      iex> PuppyLogWeb.Format.duration(120)
      "2 Std"
      iex> PuppyLogWeb.Format.duration(758)
      "12 Std 38 Min"
  """
  def duration(minutes) when minutes < 60, do: "#{minutes} Min"

  def duration(minutes) do
    case rem(minutes, 60) do
      0 -> "#{div(minutes, 60)} Std"
      rest -> "#{div(minutes, 60)} Std #{rest} Min"
    end
  end

  @doc "Display name of a user, falling back to the e-mail local part."
  def user_name(nil), do: "Unbekannt"
  def user_name(%{name: name}) when is_binary(name) and name != "", do: name
  def user_name(%{email: email}), do: email |> to_string() |> String.split("@") |> hd()

  @doc "\"Du\" for the current user, the name otherwise."
  def who(nil, _current_user), do: "Unbekannt"
  def who(%{id: id}, %{id: id}), do: "Du"
  def who(user, _current_user), do: user_name(user)

  @doc "Initials for avatars: \"Du\" for yourself, first letter otherwise."
  def initials(%{id: id}, %{id: id}), do: "Du"
  def initials(user, _current_user), do: user |> user_name() |> String.first() |> String.upcase()
end
