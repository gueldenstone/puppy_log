defmodule PuppyLog.Daily.MatchingTest do
  use ExUnit.Case, async: true

  alias PuppyLog.Daily.Matching

  @date ~D[2026-11-12]

  defp occ(time, attrs \\ []) do
    Map.merge(
      %{date: @date, planned_start: time, planned_end: nil, kind: :potty, status: :open},
      Map.new(attrs)
    )
  end

  @outside %{kind: :potty, location: :outside}

  test "tolerance is 15 minutes" do
    assert Matching.tolerance_minutes() == 15
  end

  describe "deviation_minutes/4" do
    test "point in time: late and early" do
      assert Matching.deviation_minutes(@date, ~T[10:00:00], nil, ~N[2026-11-12 10:20:00]) == 20
      assert Matching.deviation_minutes(@date, ~T[10:00:00], nil, ~N[2026-11-12 09:55:00]) == -5
    end

    test "window: inside is 0, otherwise distance to nearest edge" do
      s = ~T[12:30:00]
      e = ~T[14:00:00]
      assert Matching.deviation_minutes(@date, s, e, ~N[2026-11-12 13:00:00]) == 0
      assert Matching.deviation_minutes(@date, s, e, ~N[2026-11-12 14:20:00]) == 20
      assert Matching.deviation_minutes(@date, s, e, ~N[2026-11-12 12:00:00]) == -30
    end

    test "tick on a later day gives a large positive value" do
      assert Matching.deviation_minutes(@date, ~T[02:00:00], nil, ~N[2026-11-13 07:00:00]) == 1740
    end
  end

  test "kept?/1" do
    assert Matching.kept?(15)
    assert Matching.kept?(-15)
    refute Matching.kept?(16)
    refute Matching.kept?(nil)
  end

  describe "fulfils?/2" do
    test "potty only outside" do
      refute Matching.fulfils?(:potty, %{kind: :potty, location: :inside})
      refute Matching.fulfils?(:potty, %{kind: :potty, location: nil})
      assert Matching.fulfils?(:potty, @outside)
    end

    test "same kind for meal, walk, sleep, play" do
      for k <- [:meal, :walk, :sleep, :play] do
        assert Matching.fulfils?(k, %{kind: k, location: nil})
        refute Matching.fulfils?(k, %{kind: :other, location: nil})
      end
    end

    test "training, manual routines and vomit/other events never" do
      refute Matching.fulfils?(:training, %{kind: :play, location: nil})
      refute Matching.fulfils?(:training, %{kind: :training, location: nil})
      refute Matching.fulfils?(:manual, %{kind: :manual, location: nil})
      refute Matching.fulfils?(:potty, %{kind: :vomit, location: :outside})
      refute Matching.fulfils?(:meal, %{kind: :other, location: nil})
    end
  end

  describe "candidates/3 and auto_match/3" do
    test "auto match picks the closest kept occurrence" do
      o10 = occ(~T[10:00:00])
      o1030 = occ(~T[10:30:00])
      assert Matching.auto_match([o10, o1030], @outside, ~N[2026-11-12 10:20:00]) == o1030
      assert Matching.auto_match([o1030, o10], @outside, ~N[2026-11-12 10:14:00]) == o10
    end

    test "outside tolerance there is no auto match but candidates stay ordered" do
      o10 = occ(~T[10:00:00])
      o12 = occ(~T[12:00:00])
      actual = ~N[2026-11-12 10:40:00]
      assert Matching.auto_match([o12, o10], @outside, actual) == nil
      assert Matching.candidates([o12, o10], @outside, actual) == [o10, o12]
    end

    test "equal deviation: earlier planned start first" do
      o10 = occ(~T[10:00:00])
      o1030 = occ(~T[10:30:00])
      assert Matching.candidates([o1030, o10], @outside, ~N[2026-11-12 10:15:00]) == [o10, o1030]
    end

    test "done, skipped, other-date and non-fulfilling occurrences are not candidates" do
      actual = ~N[2026-11-12 10:00:00]

      occs = [
        occ(~T[10:00:00], status: :done),
        occ(~T[10:00:00], status: :skipped),
        occ(~T[10:00:00], date: ~D[2026-11-11]),
        occ(~T[10:00:00], kind: :meal)
      ]

      assert Matching.candidates(occs, @outside, actual) == []
      assert Matching.auto_match(occs, @outside, actual) == nil
    end
  end

  describe "state/2" do
    test "open, overdue and missed" do
      o = occ(~T[10:00:00])
      assert Matching.state(o, ~N[2026-11-12 10:15:00]) == :open
      assert Matching.state(o, ~N[2026-11-12 10:16:00]) == :overdue
      assert Matching.state(o, ~N[2026-11-13 00:00:00]) == :missed
    end

    test "overdue is measured from the window end" do
      o = occ(~T[12:00:00], planned_end: ~T[14:00:00])
      assert Matching.state(o, ~N[2026-11-12 14:15:00]) == :open
      assert Matching.state(o, ~N[2026-11-12 14:16:00]) == :overdue
    end

    test "done and skipped pass through" do
      assert Matching.state(occ(~T[10:00:00], status: :done), ~N[2026-11-14 10:00:00]) == :done

      assert Matching.state(occ(~T[10:00:00], status: :skipped), ~N[2026-11-14 10:00:00]) ==
               :skipped
    end
  end
end
