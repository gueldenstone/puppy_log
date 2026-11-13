defmodule PuppyLog.Puppy.HealthStatusTest do
  use ExUnit.Case, async: true

  alias PuppyLog.Puppy.HealthStatus

  @now DateTime.new!(~D[2026-11-13], ~T[10:00:00], "Europe/Berlin")

  defp care(due_on, attrs \\ %{}) do
    Map.merge(
      %{kind: :vaccination, due_on: due_on, due_time: nil, remind_days_before: 2, status: :open},
      attrs
    )
  end

  defp vet(due_on, due_time) do
    care(due_on, %{kind: :vet_visit, due_time: due_time})
  end

  test "care item within the lead time is due soon" do
    assert HealthStatus.state(care(~D[2026-11-15]), @now) == :due_soon
  end

  test "care item beyond the lead time is open" do
    assert HealthStatus.state(care(~D[2026-11-20]), @now) == :open
  end

  test "care item due today is due today" do
    assert HealthStatus.state(care(~D[2026-11-13]), @now) == :due_today
  end

  test "care item before today is overdue" do
    assert HealthStatus.state(care(~D[2026-11-12]), @now) == :overdue
  end

  test "vet visit is overdue after its time and due today before it" do
    assert HealthStatus.state(vet(~D[2026-11-13], ~T[09:00:00]), @now) == :overdue
    assert HealthStatus.state(vet(~D[2026-11-13], ~T[11:00:00]), @now) == :due_today
    assert HealthStatus.state(vet(~D[2026-11-12], ~T[23:00:00]), @now) == :overdue
    assert HealthStatus.state(vet(~D[2026-11-14], ~T[09:00:00]), @now) == :due_soon
  end

  test "a done entry is done" do
    assert HealthStatus.state(care(~D[2026-11-01], %{status: :done}), @now) == :done
  end

  test "evaluates in local time for a UTC now" do
    utc = DateTime.shift_zone!(@now, "Etc/UTC")
    assert HealthStatus.state(vet(~D[2026-11-13], ~T[11:00:00]), utc) == :due_today
  end

  test "days_until counts calendar days" do
    assert HealthStatus.days_until(care(~D[2026-11-16]), ~D[2026-11-13]) == 3
    assert HealthStatus.days_until(care(~D[2026-11-10]), ~D[2026-11-13]) == -3
  end
end
