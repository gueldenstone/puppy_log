defmodule PuppyLog.Puppy.DueAgeTest do
  use ExUnit.Case, async: true

  alias PuppyLog.Puppy.DueAge

  test "weeks count days from birth" do
    assert DueAge.due_on(~D[2026-10-07], 8, :weeks) == ~D[2026-12-02]
  end

  test "months keep the day and clamp to month end" do
    assert DueAge.due_on(~D[2026-10-07], 4, :months) == ~D[2027-02-07]
    assert DueAge.due_on(~D[2027-01-31], 1, :months) == ~D[2027-02-28]
  end

  test "labels" do
    assert DueAge.label(1, :weeks) == "mit 1 Woche"
    assert DueAge.label(8, :weeks) == "mit 8 Wochen"
    assert DueAge.label(1, :months) == "mit 1 Monat"
    assert DueAge.label(4, :months) == "mit 4 Monaten"
  end
end
