defmodule PuppyLogWeb.WeightChartTest do
  use ExUnit.Case, async: true

  alias PuppyLogWeb.WeightChart

  doctest PuppyLogWeb.Format

  defp entry(date, grams), do: %{measured_on: date, weight_grams: grams}

  test "needs at least two entries" do
    assert WeightChart.build([entry(~D[2026-10-01], 4000)], nil) == :too_few
  end

  test "uses weeks of life when the birth date is known" do
    model =
      WeightChart.build(
        [entry(~D[2026-10-08], 4600), entry(~D[2026-10-01], 4000), entry(~D[2026-10-15], 5200)],
        ~D[2026-08-06]
      )

    assert length(model.points) == 3
    # oldest entry is drawn on the left, heaviest at the top
    [first, _, last] = model.points
    assert first.x < last.x
    assert last.y < first.y
    assert List.last(model.x_ticks).label == "10 W."
    assert model.label =~ "Lebenswochen: von 4 kg auf 5,2 kg"
    assert Enum.all?(model.y_ticks, &(&1.y >= 12 and &1.y <= 112))
  end

  test "falls back to dates" do
    model = WeightChart.build([entry(~D[2026-10-01], 4000), entry(~D[2026-10-08], 4000)], nil)
    assert Enum.map(model.x_ticks, & &1.label) == ["1.10.", "8.10."]
  end
end
