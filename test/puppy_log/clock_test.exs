defmodule PuppyLog.ClockTest do
  use ExUnit.Case, async: false

  import PuppyLog.Fixtures

  alias PuppyLog.Clock

  test "local_datetime moves a time in the spring-forward gap to the later valid time" do
    dt = Clock.local_datetime(~D[2026-03-29], ~T[02:30:00])

    assert DateTime.to_naive(dt) == ~N[2026-03-29 03:30:00]
    assert dt.zone_abbr == "CEST"
  end

  test "local_datetime takes the first of an ambiguous time" do
    dt = Clock.local_datetime(~D[2026-10-25], ~T[02:30:00])

    assert DateTime.to_naive(dt) == ~N[2026-10-25 02:30:00]
    assert dt.zone_abbr == "CEST"
  end

  test "day_bounds are the UTC start of the day and of the next day" do
    assert Clock.day_bounds(~D[2026-11-12]) ==
             {~U[2026-11-11 23:00:00Z], ~U[2026-11-12 23:00:00Z]}
  end

  test "now and today follow the clock_now override" do
    pin_clock(~U[2026-11-12 23:30:00Z])

    assert Clock.now() |> DateTime.to_naive() == ~N[2026-11-13 00:30:00]
    assert Clock.today() == ~D[2026-11-13]
  end
end
