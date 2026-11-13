defmodule PuppyLog.Puppy.CalendarTest do
  use ExUnit.Case, async: true

  alias PuppyLog.Puppy.{Calendar, HealthEntry}

  @riv_id "11111111-1111-1111-1111-111111111111"

  defp entry(attrs) do
    struct!(
      HealthEntry,
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          kind: :deworming,
          title: "Wurmkur",
          due_on: ~D[2026-11-20],
          remind_days_before: 2,
          status: :open
        },
        attrs
      )
    )
  end

  defp render(entries, opts \\ []) do
    entries
    |> Calendar.render(
      Keyword.merge([name: "Puppy Log – Bruno", users: %{@riv_id => "Riv"}], opts)
    )
    |> IO.iodata_to_binary()
  end

  # Unfolds continuation lines so assertions can look at whole content lines.
  defp lines(ics), do: ics |> String.replace("\r\n ", "") |> String.split("\r\n", trim: true)

  test "calendar header" do
    lines = render([]) |> lines()

    assert ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Puppy Log//DE" | _] = lines
    assert "CALSCALE:GREGORIAN" in lines
    assert "X-WR-CALNAME:Puppy Log – Bruno" in lines
    assert "REFRESH-INTERVAL;VALUE=DURATION:PT1H" in lines
    assert "X-PUBLISHED-TTL:PT1H" in lines
    assert List.last(lines) == "END:VCALENDAR"
  end

  test "all-day care item with alarm at 09:00 two days before" do
    e =
      entry(%{kind: :deworming, title: "Wurmkur", due_on: ~D[2026-11-20], remind_days_before: 2})

    lines = render([e]) |> lines()

    assert "BEGIN:VEVENT" in lines
    assert "UID:#{e.id}@puppy-log" in lines
    assert Enum.any?(lines, &Regex.match?(~r/\ADTSTAMP:\d{8}T\d{6}Z\z/, &1))
    assert "DTSTART;VALUE=DATE:20261120" in lines
    assert "DTEND;VALUE=DATE:20261121" in lines
    assert "SUMMARY:Wurmkur" in lines
    assert "DESCRIPTION:Entwurmung" in lines
    assert "BEGIN:VALARM" in lines
    assert "ACTION:DISPLAY" in lines
    assert "TRIGGER;RELATED=START:-P1DT15H" in lines
    assert "DESCRIPTION:Wurmkur" in lines
  end

  test "care alarm lead times map to 09:00 local" do
    triggers =
      for n <- [0, 1, 3] do
        [entry(%{remind_days_before: n})]
        |> render()
        |> lines()
        |> Enum.find(&String.starts_with?(&1, "TRIGGER"))
      end

    assert triggers == [
             "TRIGGER;RELATED=START:PT9H",
             "TRIGGER;RELATED=START:-PT15H",
             "TRIGGER;RELATED=START:-P2DT15H"
           ]
  end

  test "vet appointment in UTC with two alarms" do
    e =
      entry(%{
        kind: :vet_visit,
        title: "Tierarzt",
        due_on: ~D[2026-11-20],
        due_time: ~T[10:00:00],
        location: "Praxis Dr. Huf",
        assignee_id: @riv_id,
        remind_days_before: 2
      })

    lines = render([e]) |> lines()

    assert "DTSTART:20261120T090000Z" in lines
    assert "DTEND:20261120T100000Z" in lines
    assert "LOCATION:Praxis Dr. Huf" in lines
    assert "DESCRIPTION:Geht hin: Riv\\nTierarzt" in lines
    assert "TRIGGER:-P2D" in lines
    assert "TRIGGER:-PT2H" in lines
    assert Enum.count(lines, &(&1 == "BEGIN:VALARM")) == 2
  end

  test "vet appointment on the day only gets the two-hour alarm" do
    e = entry(%{kind: :vet_visit, due_time: ~T[10:00:00], remind_days_before: 0})
    triggers = render([e]) |> lines() |> Enum.filter(&String.starts_with?(&1, "TRIGGER"))
    assert triggers == ["TRIGGER:-PT2H"]
  end

  test "DST: 2026-03-29 10:00 is 08:00 UTC" do
    e = entry(%{kind: :vet_visit, due_on: ~D[2026-03-29], due_time: ~T[10:00:00]})
    lines = render([e]) |> lines()

    assert "DTSTART:20260329T080000Z" in lines
    assert "DTEND:20260329T090000Z" in lines
  end

  test "description lists notes, batch and kind" do
    e = entry(%{kind: :vaccination, notes: "Nüchtern kommen", batch: "A123"})
    lines = render([e]) |> lines()

    assert "DESCRIPTION:Nüchtern kommen\\nImpfstoff/Charge: A123\\nImpfung" in lines
  end

  test "an age entry mentions the age in the description" do
    e = entry(%{due_age: 8, due_age_unit: :weeks})
    lines = render([e]) |> lines()

    assert "DESCRIPTION:mit 8 Wochen\\nEntwurmung" in lines
    assert "SUMMARY:Wurmkur" in lines
  end

  test "done entries are ticked and have no alarm" do
    e = entry(%{status: :done, done_on: ~D[2026-11-19]})
    lines = render([e]) |> lines()

    assert "SUMMARY:✓ Wurmkur" in lines
    refute "BEGIN:VALARM" in lines
    refute Enum.any?(lines, &String.starts_with?(&1, "TRIGGER"))
  end

  test "escapes , ; \\ and newlines" do
    e = entry(%{title: "A, B; C\\D", notes: "Zeile 1\nZeile 2\r\nZeile 3"})
    lines = render([e]) |> lines()

    assert "SUMMARY:A\\, B\\; C\\\\D" in lines
    assert "DESCRIPTION:Zeile 1\\nZeile 2\\nZeile 3\\nEntwurmung" in lines
  end

  test "folds long umlaut lines at 75 octets, CRLF everywhere" do
    notes = String.duplicate("Ä", 100) <> String.duplicate("ü", 3)
    ics = render([entry(%{notes: notes})])

    # Every line ends with CRLF, no bare LF or CR
    assert String.ends_with?(ics, "\r\n")
    refute ics |> String.replace("\r\n", "") |> String.contains?(["\n", "\r"])

    physical = String.split(ics, "\r\n", trim: true)
    assert Enum.all?(physical, &(byte_size(&1) <= 75))
    assert Enum.all?(physical, &String.valid?/1)
    assert Enum.any?(physical, &String.starts_with?(&1, " "))

    assert "DESCRIPTION:#{notes}\\nEntwurmung" in lines(ics)
  end
end
