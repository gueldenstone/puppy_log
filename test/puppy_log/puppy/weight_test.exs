defmodule PuppyLog.Puppy.WeightTest do
  use ExUnit.Case, async: true

  alias PuppyLog.Puppy.Weight

  doctest Weight
  doctest PuppyLog.Puppy.Age

  test "parse_kg handles German input" do
    assert Weight.parse_kg(" 0,8 ") == {:ok, 800}
    assert Weight.parse_kg("4,355") == {:ok, 4355}
    assert Weight.parse_kg("7 KG") == {:ok, 7000}
    assert Weight.parse_kg("") == :error
    assert Weight.parse_kg("-2") == :error
    assert Weight.parse_kg(nil) == :error
  end

  test "format_delta" do
    assert Weight.format_delta(350) == "+350 g"
    assert Weight.format_delta(-120) == "−120 g"
    assert Weight.format_delta(1200) == "+1,2 kg"
    assert Weight.format_delta(0) == "±0 g"
  end
end
