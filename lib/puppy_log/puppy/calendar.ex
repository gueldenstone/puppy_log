defmodule PuppyLog.Puppy.Calendar do
  @moduledoc """
  Renders health entries as an iCalendar (RFC 5545) feed for calendar subscriptions.

  Pure: takes entries and names, returns iodata. Care items become all-day events,
  vet visits one-hour events in UTC. Open entries carry the `VALARM`s that are the
  household's only reminders for health entries.
  """

  alias PuppyLog.Clock
  alias PuppyLog.Puppy.DueAge

  @kind_labels %{
    vaccination: "Impfung",
    deworming: "Entwurmung",
    flea_tick: "Floh/Zecke",
    other_care: "Andere Vorsorge",
    vet_visit: "Tierarzt"
  }

  @vet_duration_seconds 60 * 60
  @max_line_octets 75

  @doc """
  Renders `entries` as a VCALENDAR.

  Options:
    * `:name` – calendar name (`X-WR-CALNAME`)
    * `:users` – map of user id to display name, for „Geht hin: …“
    * `:now` – generation time for `DTSTAMP` (defaults to `Clock.utc_now/0`)
  """
  @spec render([map()], keyword()) :: iodata()
  def render(entries, opts) do
    users = Keyword.get(opts, :users, %{})
    stamp = opts |> Keyword.get_lazy(:now, &Clock.utc_now/0) |> format_utc()

    header = [
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//Puppy Log//DE",
      "CALSCALE:GREGORIAN",
      "X-WR-CALNAME:" <> escape(Keyword.fetch!(opts, :name)),
      "REFRESH-INTERVAL;VALUE=DURATION:PT1H",
      "X-PUBLISHED-TTL:PT1H"
    ]

    events = Enum.flat_map(entries, &event(&1, users, stamp))

    Enum.map(header ++ events ++ ["END:VCALENDAR"], &[fold(&1), "\r\n"])
  end

  defp event(entry, users, stamp) do
    List.flatten([
      "BEGIN:VEVENT",
      "UID:#{entry.id}@puppy-log",
      "DTSTAMP:" <> stamp,
      timing(entry),
      "SUMMARY:" <> escape(summary(entry)),
      optional("LOCATION", entry.location),
      optional("DESCRIPTION", description(entry, users)),
      alarms(entry),
      "END:VEVENT"
    ])
  end

  defp timing(%{kind: :vet_visit, due_on: date, due_time: %Time{} = time}) do
    start = Clock.local_datetime(date, time)

    [
      "DTSTART:" <> format_utc(start),
      "DTEND:" <> format_utc(DateTime.add(start, @vet_duration_seconds, :second))
    ]
  end

  defp timing(%{due_on: date}) do
    [
      "DTSTART;VALUE=DATE:" <> format_date(date),
      "DTEND;VALUE=DATE:" <> format_date(Date.add(date, 1))
    ]
  end

  defp summary(%{status: :done, title: title}), do: "✓ " <> title
  defp summary(%{title: title}), do: title

  defp description(entry, users) do
    [
      age_line(entry),
      entry.notes,
      assignee_line(entry, users),
      entry.batch && "Impfstoff/Charge: " <> entry.batch,
      Map.fetch!(@kind_labels, entry.kind)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join("\n")
  end

  defp age_line(%{due_age: age, due_age_unit: unit}) when is_integer(age) and not is_nil(unit),
    do: DueAge.label(age, unit)

  defp age_line(_entry), do: nil

  defp assignee_line(%{assignee_id: nil}, _users), do: nil

  defp assignee_line(%{assignee_id: id}, users) do
    case Map.get(users, id) do
      nil -> nil
      name -> "Geht hin: " <> name
    end
  end

  defp alarms(%{status: :done}), do: []

  defp alarms(%{kind: :vet_visit, remind_days_before: 0} = entry),
    do: [alarm(entry, "TRIGGER:-PT2H")]

  defp alarms(%{kind: :vet_visit, remind_days_before: days} = entry),
    do: [alarm(entry, "TRIGGER:-P#{days}D"), alarm(entry, "TRIGGER:-PT2H")]

  # All-day events start at local midnight; the alarm fires at 09:00 N days before.
  defp alarms(%{remind_days_before: 0} = entry),
    do: [alarm(entry, "TRIGGER;RELATED=START:PT9H")]

  defp alarms(%{remind_days_before: 1} = entry),
    do: [alarm(entry, "TRIGGER;RELATED=START:-PT15H")]

  defp alarms(%{remind_days_before: days} = entry),
    do: [alarm(entry, "TRIGGER;RELATED=START:-P#{days - 1}DT15H")]

  defp alarm(entry, trigger) do
    [
      "BEGIN:VALARM",
      "ACTION:DISPLAY",
      trigger,
      "DESCRIPTION:" <> escape(entry.title),
      "END:VALARM"
    ]
  end

  defp optional(_name, value) when value in [nil, ""], do: []
  defp optional(name, value), do: name <> ":" <> escape(value)

  defp blank?(value), do: value in [nil, ""]

  defp format_date(date), do: Calendar.strftime(date, "%Y%m%d")

  defp format_utc(datetime) do
    datetime |> DateTime.shift_zone!("Etc/UTC") |> Calendar.strftime("%Y%m%dT%H%M%SZ")
  end

  # RFC 5545 §3.3.11 TEXT escaping.
  defp escape(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\\;")
    |> String.replace(",", "\\,")
    |> String.replace(~r/\r\n|\r|\n/, "\\n")
  end

  # RFC 5545 §3.1: lines longer than 75 octets continue on lines starting with a
  # space; never split inside a UTF-8 code point.
  defp fold(line) when byte_size(line) <= @max_line_octets, do: line

  defp fold(line) do
    {first, rest} = split_at_octets(line, @max_line_octets)
    [first | fold_rest(rest)]
  end

  defp fold_rest(""), do: []

  defp fold_rest(rest) do
    {chunk, rest} = split_at_octets(rest, @max_line_octets - 1)
    ["\r\n ", chunk | fold_rest(rest)]
  end

  defp split_at_octets(string, max) do
    size =
      string
      |> String.codepoints()
      |> Enum.reduce_while(0, fn codepoint, size ->
        new_size = size + byte_size(codepoint)
        if new_size > max, do: {:halt, size}, else: {:cont, new_size}
      end)

    <<head::binary-size(^size), tail::binary>> = string
    {head, tail}
  end
end
