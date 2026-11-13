defmodule PuppyLogWeb.TimeChoiceTest do
  use ExUnit.Case, async: true

  alias PuppyLog.Clock
  alias PuppyLogWeb.TimeChoice

  @now Clock.local_datetime(~D[2026-11-12], ~T[10:30:00])

  test "offers the quick choices" do
    assert TimeChoice.options() == [
             {"Jetzt", "now"},
             {"vor 15 Min", "15"},
             {"vor 20 Min", "20"},
             {"vor 30 Min", "30"},
             {"Uhrzeit", "custom"}
           ]
  end

  test "now and minutes ago" do
    assert {:ok, now} = TimeChoice.resolve("now", nil, @now)
    assert DateTime.compare(now, @now) == :eq

    assert {:ok, earlier} = TimeChoice.resolve("15", nil, @now)
    assert local_time(earlier) == ~T[10:15:00]

    assert {:ok, earlier} = TimeChoice.resolve("30", "", @now)
    assert local_time(earlier) == ~T[10:00:00]
  end

  test "custom time is Berlin wall-clock time" do
    assert {:ok, at} = TimeChoice.resolve("custom", "2026-11-12T09:05", @now)
    assert DateTime.compare(at, Clock.local_datetime(~D[2026-11-12], ~T[09:05:00])) == :eq
    assert local_time(at) == ~T[09:05:00]
  end

  test "custom time in the future is rejected" do
    assert TimeChoice.resolve("custom", "2026-11-12T10:31", @now) == :error
  end

  test "garbage is rejected" do
    assert TimeChoice.resolve("custom", "gestern", @now) == :error
    assert TimeChoice.resolve("custom", nil, @now) == :error
    assert TimeChoice.resolve("45", nil, @now) == :error
    assert TimeChoice.resolve("bald", nil, @now) == :error
  end

  defp local_time(datetime), do: datetime |> Clock.local() |> DateTime.to_time()
end
