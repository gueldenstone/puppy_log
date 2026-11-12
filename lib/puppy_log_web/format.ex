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

  def weekday(%Date{} = date), do: Enum.at(@weekdays, Date.day_of_week(date) - 1)

  @doc ~S"""
  Groups a 15 digit chip number for reading: "276 098 106 543 210".

      iex> PuppyLogWeb.Format.chip_number("276098106543210")
      "276 098 106 543 210"
  """
  def chip_number(nil), do: nil

  def chip_number(number) do
    number |> String.graphemes() |> Enum.chunk_every(3) |> Enum.map_join(" ", &Enum.join/1)
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
