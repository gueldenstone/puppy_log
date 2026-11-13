defmodule PuppyLog.Daily.RemindersTest do
  use PuppyLog.DataCase, async: false

  alias PuppyLog.{Accounts, Clock, Daily}
  alias PuppyLog.Daily.{Reminders, Settings}
  alias PuppyLog.Notifications.Push

  @today ~D[2026-11-12]

  setup do
    lukas = user_fixture(%{name: "Lukas"})
    riv = user_fixture(%{name: "Riv"})
    pin_clock(Clock.local_datetime(~D[2026-11-01], ~T[06:00:00]))

    {:ok, _} =
      PuppyLog.Puppy.create_profile(%{name: "Fiete", arrival_date: ~D[2026-11-01]},
        actor: lukas
      )

    {lukas_sub, lukas_keys} = subscription_fixture(lukas)
    {riv_sub, riv_keys} = subscription_fixture(riv)

    devices = %{
      URI.parse(lukas_sub.endpoint).path => {:lukas, lukas_keys},
      URI.parse(riv_sub.endpoint).path => {:riv, riv_keys}
    }

    test_pid = self()

    Req.Test.stub(Push, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      {who, keys} = Map.fetch!(devices, conn.request_path)
      send(test_pid, {:push, who, body |> decrypt_push(keys) |> Jason.decode!()})
      Plug.Conn.send_resp(conn, 201, "")
    end)

    %{lukas: lukas, riv: riv}
  end

  defp routine(actor, attrs) do
    {:ok, routine} =
      Daily.create_routine(Map.merge(%{name: "Gassi", kind: :walk}, attrs), actor: actor)

    routine
  end

  defp at(time, date \\ @today), do: Clock.local_datetime(date, time)

  defp tick(time, date \\ @today), do: :ok = Reminders.tick(at(time, date))

  defp occurrence_of(routine, actor) do
    @today
    |> Daily.list_occurrences_on!(actor: actor)
    |> Enum.find(&(&1.routine_id == routine.id))
  end

  defp pushed do
    receive do
      {:push, who, payload} -> [{who, payload} | pushed()]
    after
      0 -> []
    end
  end

  defp titles, do: pushed() |> Enum.map(fn {_who, payload} -> payload["title"] end)

  test "sends at the planned minute once", %{lukas: lukas} do
    routine = routine(lukas, %{starts_at: ~T[10:00:00]})

    tick(~T[09:59:00])
    assert pushed() == []

    tick(~T[10:00:00])
    assert [{_, payload}, {_, payload}] = pushed()

    assert payload == %{
             "title" => "Gassi",
             "body" => "Jetzt fällig (10:00).",
             "tag" => "routine-#{occurrence_of(routine, lukas).id}",
             "url" => "/"
           }

    assert DateTime.compare(occurrence_of(routine, lukas).reminded_at, at(~T[10:00:00])) == :eq

    tick(~T[10:01:00])
    assert pushed() == []
  end

  test "a window routine names its window", %{lukas: lukas} do
    routine(lukas, %{starts_at: ~T[12:30:00], ends_at: ~T[14:00:00]})

    tick(~T[12:30:00])
    assert [{_, %{"body" => "Zwischen 12:30 und 14:00."}} | _] = pushed()
  end

  test "routines without reminder are not pushed", %{lukas: lukas} do
    routine(lukas, %{starts_at: ~T[10:00:00], remind?: false})

    tick(~T[10:00:00])
    assert pushed() == []
  end

  test "not more than 10 minutes late", %{lukas: lukas} do
    routine = routine(lukas, %{starts_at: ~T[10:00:00]})

    tick(~T[10:11:00])
    assert pushed() == []
    assert occurrence_of(routine, lukas).reminded_at == nil
  end

  test "a late tick within 10 minutes still reminds", %{lukas: lukas} do
    routine(lukas, %{starts_at: ~T[10:00:00]})

    tick(~T[10:10:00])
    assert titles() == ["Gassi", "Gassi"]
  end

  test "follow-up after 30 minutes if still open", %{lukas: lukas} do
    routine = routine(lukas, %{starts_at: ~T[10:00:00], follow_up_minutes: 30})

    tick(~T[10:00:00])
    assert titles() == ["Gassi", "Gassi"]

    tick(~T[10:29:00])
    assert pushed() == []

    tick(~T[10:30:00])
    assert [{_, payload}, {_, _}] = pushed()

    assert payload == %{
             "title" => "Gassi noch offen",
             "body" => "Seit 30 Minuten fällig.",
             "tag" => "routine-#{occurrence_of(routine, lukas).id}",
             "url" => "/"
           }

    assert DateTime.compare(occurrence_of(routine, lukas).follow_up_sent_at, at(~T[10:30:00])) ==
             :eq

    tick(~T[10:31:00])
    assert pushed() == []
  end

  test "no follow-up when done", %{lukas: lukas} do
    routine = routine(lukas, %{starts_at: ~T[10:00:00], follow_up_minutes: 30})

    tick(~T[10:00:00])
    assert titles() == ["Gassi", "Gassi"]

    {:ok, _} =
      Daily.complete_occurrence(occurrence_of(routine, lukas), %{done_at: at(~T[10:15:00])},
        actor: lukas
      )

    # the done notification for the other phone
    assert titles() == ["Gassi erledigt ✓"]

    tick(~T[10:30:00])
    assert pushed() == []
  end

  test "no follow-up without a reminder", %{lukas: lukas} do
    routine(lukas, %{starts_at: ~T[10:00:00], follow_up_minutes: 30})

    tick(~T[10:30:00])
    assert pushed() == []
  end

  test "quiet hours 22:00–06:30", %{lukas: lukas} do
    {:ok, _} = Daily.save_settings(%{quiet_hours_enabled: true}, actor: lukas)

    routine(lukas, %{name: "Spät", starts_at: ~T[23:00:00], follow_up_minutes: 15})
    routine(lukas, %{name: "Früh", starts_at: ~T[05:00:00]})
    routine(lukas, %{name: "Morgens", starts_at: ~T[07:00:00]})

    for time <- [~T[05:00:00], ~T[05:10:00], ~T[06:30:00], ~T[06:40:00]], do: tick(time)
    assert pushed() == []

    tick(~T[07:00:00])
    assert titles() == ["Morgens", "Morgens"]

    for time <- [~T[23:00:00], ~T[23:10:00], ~T[23:15:00]], do: tick(time)
    tick(~T[00:05:00], Date.add(@today, 1))
    assert pushed() == []
  end

  test "quiet? handles ranges across midnight and by day" do
    night = %Settings{
      quiet_hours_enabled: true,
      quiet_from: ~T[22:00:00],
      quiet_until: ~T[06:30:00]
    }

    assert Reminders.quiet?(night, ~T[22:00:00])
    assert Reminders.quiet?(night, ~T[03:00:00])
    assert Reminders.quiet?(night, ~T[06:29:59])
    refute Reminders.quiet?(night, ~T[06:30:00])
    refute Reminders.quiet?(night, ~T[12:00:00])
    refute Reminders.quiet?(%{night | quiet_hours_enabled: false}, ~T[23:00:00])

    noon = %{night | quiet_from: ~T[12:00:00], quiet_until: ~T[14:00:00]}
    assert Reminders.quiet?(noon, ~T[13:00:00])
    refute Reminders.quiet?(noon, ~T[14:00:00])
    refute Reminders.quiet?(noon, ~T[23:00:00])
  end

  test "only members with reminders on get pushes", %{lukas: lukas, riv: riv} do
    {:ok, _} = Accounts.set_reminders(riv, %{receives_reminders: false}, actor: riv)
    routine(lukas, %{starts_at: ~T[10:00:00]})

    tick(~T[10:00:00])
    assert [{:lukas, %{"title" => "Gassi"}}] = pushed()
  end

  @doc false
  def failing_clock, do: raise("clock broken")

  test "a failing tick is logged and the next minute is scheduled" do
    Application.put_env(:puppy_log, :clock_now, {__MODULE__, :failing_clock})

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert {:noreply, timer} = Reminders.handle_info(:tick, nil)
        assert Process.cancel_timer(timer) in 1..60_000
      end)

    assert log =~ "Reminder tick failed"
    assert log =~ "clock broken"
  end

  describe "done notifications" do
    test "done replaces the reminder on the other phone", %{lukas: lukas} do
      routine = routine(lukas, %{starts_at: ~T[10:00:00]})
      tick(~T[10:00:00])
      assert titles() == ["Gassi", "Gassi"]

      occurrence = occurrence_of(routine, lukas)

      {:ok, _} =
        Daily.complete_occurrence(occurrence, %{done_at: at(~T[10:05:00])}, actor: lukas)

      assert [
               {:riv,
                %{
                  "title" => "Gassi erledigt ✓",
                  "body" => "Lukas, 10:05",
                  "tag" => tag,
                  "url" => "/"
                }}
             ] = pushed()

      assert tag == "routine-#{occurrence.id}"
    end

    test "skipped tells the other phone too", %{lukas: lukas, riv: riv} do
      routine = routine(lukas, %{starts_at: ~T[10:00:00]})
      tick(~T[10:00:00])
      assert titles() == ["Gassi", "Gassi"]

      {:ok, _} = Daily.skip_occurrence(occurrence_of(routine, lukas), actor: riv)

      assert [{:lukas, %{"title" => "Gassi übersprungen", "body" => "Riv"}}] = pushed()
    end

    test "an event that fulfils the routine counts as done", %{lukas: lukas, riv: riv} do
      routine(lukas, %{name: "Lösen", kind: :potty, starts_at: ~T[10:00:00]})
      tick(~T[10:00:00])
      assert titles() == ["Lösen", "Lösen"]

      {:ok, _} =
        Daily.log_event(
          %{kind: :potty, pee: true, location: :outside, occurred_at: at(~T[10:04:00])},
          actor: riv
        )

      assert [{:lukas, %{"title" => "Lösen erledigt ✓", "body" => "Riv, 10:04"}}] = pushed()
    end

    test "not reminded → nothing sent", %{lukas: lukas} do
      routine = routine(lukas, %{starts_at: ~T[10:00:00]})
      :ok = Daily.ensure_day(@today)

      {:ok, _} =
        Daily.complete_occurrence(occurrence_of(routine, lukas), %{done_at: at(~T[09:30:00])},
          actor: lukas
        )

      assert pushed() == []
    end

    test "a reopened occurrence is not reminded again", %{lukas: lukas} do
      routine = routine(lukas, %{starts_at: ~T[10:00:00]})
      tick(~T[10:00:00])
      assert titles() == ["Gassi", "Gassi"]

      {:ok, done} =
        Daily.complete_occurrence(occurrence_of(routine, lukas), %{done_at: at(~T[10:01:00])},
          actor: lukas
        )

      assert titles() == ["Gassi erledigt ✓"]
      {:ok, _} = Daily.reopen_occurrence(done, actor: lukas)

      tick(~T[10:02:00])
      assert pushed() == []
    end

    test "two completions send one done notification", %{lukas: lukas, riv: riv} do
      routine = routine(lukas, %{starts_at: ~T[10:00:00]})
      tick(~T[10:00:00])
      assert titles() == ["Gassi", "Gassi"]

      occurrence = occurrence_of(routine, lukas)
      done_at = at(~T[10:05:00])

      {:ok, _} = Daily.complete_occurrence(occurrence, %{done_at: done_at}, actor: lukas)

      assert {:error, %Ash.Error.Invalid{}} =
               Daily.complete_occurrence(occurrence, %{done_at: done_at}, actor: riv)

      assert [{:riv, %{"title" => "Gassi erledigt ✓"}}] = pushed()
    end
  end
end
