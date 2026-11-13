defmodule PuppyLog.Daily.EventTest do
  use PuppyLog.DataCase, async: false

  alias PuppyLog.{Clock, Daily}

  @today ~D[2026-11-12]
  @yesterday ~D[2026-11-11]

  setup do
    lukas = user_fixture(%{name: "Lukas"})
    riv = user_fixture(%{name: "Riv"})
    pin_local(~D[2026-11-01], ~T[06:00:00])

    {:ok, _} =
      PuppyLog.Puppy.create_profile(%{name: "Fiete", arrival_date: ~D[2026-11-01]},
        actor: lukas
      )

    routine(lukas, :potty, ~T[10:00:00])
    routine(lukas, :potty, ~T[12:00:00])

    pin_local(@today, ~T[13:00:00])

    %{lukas: lukas, riv: riv}
  end

  defp pin_local(date, time), do: pin_clock(Clock.local_datetime(date, time))

  defp at(date \\ @today, time), do: Clock.local_datetime(date, time)

  defp routine(actor, kind, starts_at, name \\ "Lösen") do
    {:ok, routine} =
      Daily.create_routine(%{name: name, kind: kind, starts_at: starts_at}, actor: actor)

    routine
  end

  # A routine that already existed on `date` (routines are planned from their creation on).
  defp routine_since(actor, date, kind, starts_at, name) do
    pin_local(Date.add(date, -1), ~T[06:00:00])
    routine = routine(actor, kind, starts_at, name)
    pin_local(@today, ~T[13:00:00])
    routine
  end

  defp occurrence(actor, date \\ @today, starts_at) do
    :ok = Daily.ensure_day(date)

    Daily.list_occurrences_on!(date, actor: actor)
    |> Enum.find(&(&1.planned_start == starts_at))
  end

  defp meal_ticked_by_hand(actor, ticked_by, time) do
    meal = routine_since(actor, @today, :meal, time, "Futter")
    :ok = Daily.ensure_day(@today)

    occ =
      Daily.list_occurrences_on!(@today, actor: actor)
      |> Enum.find(&(&1.routine_id == meal.id))

    {:ok, ticked} = Daily.complete_occurrence(occ, %{done_at: at(time)}, actor: ticked_by)
    ticked
  end

  defp potty(attrs), do: Map.merge(%{kind: :potty, pee: true, location: :outside}, attrs)

  defp errors_on(error, field) do
    error
    |> Map.get(:errors)
    |> Enum.filter(&(Map.get(&1, :field) == field))
    |> Enum.map(& &1.message)
  end

  describe "linking on log" do
    test "outside pee at 10:10 fulfils the 10:00 routine", %{lukas: lukas} do
      {:ok, event} = Daily.log_event(potty(%{occurred_at: at(~T[10:10:00])}), actor: lukas)

      occ = occurrence(lukas, ~T[10:00:00])
      assert occ.status == :done
      assert occ.event_id == event.id
      assert occ.deviation_minutes == 10
      assert occ.done_at == event.occurred_at
      assert occ.completed_by_id == lukas.id

      assert occurrence(lukas, ~T[12:00:00]).status == :open
      assert Ash.load!(event, :occurrence, actor: lukas).occurrence.id == occ.id
      assert event.created_by_id == lukas.id
      assert event.link_mode == :completed
    end

    test "pee and poo in one entry fulfil one routine only", %{lukas: lukas} do
      {:ok, _} =
        Daily.log_event(potty(%{poo: true, occurred_at: at(~T[10:10:00])}), actor: lukas)

      assert [:done, :open] =
               Daily.list_occurrences_on!(@today, actor: lukas) |> Enum.map(& &1.status)
    end

    test "accident inside fulfils nothing", %{lukas: lukas} do
      {:ok, event} =
        Daily.log_event(potty(%{location: :inside, occurred_at: at(~T[10:00:00])}),
          actor: lukas
        )

      assert event.location == :inside
      assert occurrence(lukas, ~T[10:00:00]).status == :open
    end

    test "nothing outside fulfils the routine", %{lukas: lukas} do
      {:ok, event} =
        Daily.log_event(
          %{kind: :potty, nothing: true, location: :outside, occurred_at: at(~T[09:55:00])},
          actor: lukas
        )

      occ = occurrence(lukas, ~T[10:00:00])
      assert occ.status == :done
      assert occ.event_id == event.id
      assert occ.deviation_minutes == -5
    end

    test "routine none keeps the routines open", %{lukas: lukas} do
      {:ok, _} =
        Daily.log_event(potty(%{occurred_at: at(~T[10:00:00]), routine: "none"}), actor: lukas)

      assert occurrence(lukas, ~T[10:00:00]).status == :open
    end

    test "outside tolerance needs a choice", %{lukas: lukas} do
      {:ok, _} =
        Daily.log_event(potty(%{occurred_at: at(~T[10:40:00]), routine: "auto"}), actor: lukas)

      assert Enum.all?(Daily.list_occurrences_on!(@today, actor: lukas), &(&1.status == :open))

      occ_1000 = occurrence(lukas, ~T[10:00:00])

      {:ok, event} =
        Daily.log_event(potty(%{occurred_at: at(~T[10:40:00]), routine: occ_1000.id}),
          actor: lukas
        )

      occ = occurrence(lukas, ~T[10:00:00])
      assert occ.status == :done
      assert occ.event_id == event.id
      assert occ.deviation_minutes == 40
    end

    test "an explicit routine that is not a candidate is rejected", %{lukas: lukas} do
      occ_1000 = occurrence(lukas, ~T[10:00:00])
      meal = routine(lukas, :meal, ~T[15:00:00], "Futter")
      :ok = Daily.ensure_day(@today)

      meal_occ =
        Daily.list_occurrences_on!(@today, actor: lukas)
        |> Enum.find(&(&1.routine_id == meal.id))

      for routine <- [meal_occ.id, Ash.UUID.generate(), "kaputt"] do
        assert {:error, %Ash.Error.Invalid{} = error} =
                 Daily.log_event(potty(%{occurred_at: at(~T[10:40:00]), routine: routine}),
                   actor: lukas
                 )

        assert errors_on(error, :routine) != []
      end

      # an inside accident cannot fulfil a potty routine
      assert {:error, %Ash.Error.Invalid{}} =
               Daily.log_event(
                 potty(%{location: :inside, occurred_at: at(~T[10:00:00]), routine: occ_1000.id}),
                 actor: lukas
               )

      # an occurrence that is already done
      {:ok, _} = Daily.log_event(potty(%{occurred_at: at(~T[10:00:00])}), actor: lukas)

      assert {:error, %Ash.Error.Invalid{}} =
               Daily.log_event(potty(%{occurred_at: at(~T[10:05:00]), routine: occ_1000.id}),
                 actor: lukas
               )

      assert Daily.list_events_on!(@today, actor: lukas) |> length() == 1
    end

    test "an explicit routine of the previous day is allowed", %{lukas: lukas} do
      late = routine_since(lukas, @yesterday, :potty, ~T[23:50:00], "Spät")
      :ok = Daily.ensure_day(@yesterday)

      occ =
        Daily.list_occurrences_on!(@yesterday, actor: lukas)
        |> Enum.find(&(&1.routine_id == late.id))

      {:ok, event} =
        Daily.log_event(potty(%{occurred_at: at(~T[00:05:00]), routine: occ.id}), actor: lukas)

      done = Daily.get_occurrence!(occ.id, actor: lukas)
      assert done.status == :done
      assert done.event_id == event.id
      assert done.deviation_minutes == 15
    end

    test "back-dated event matches yesterday's routine", %{lukas: lukas} do
      {:ok, event} =
        Daily.log_event(potty(%{occurred_at: at(@yesterday, ~T[10:05:00])}), actor: lukas)

      yesterday_occ = occurrence(lukas, @yesterday, ~T[10:00:00])
      assert yesterday_occ.status == :done
      assert yesterday_occ.event_id == event.id
      assert occurrence(lukas, ~T[10:00:00]).status == :open
    end

    test "event at 00:10 local belongs to that day", %{lukas: lukas} do
      routine_since(lukas, @yesterday, :potty, ~T[00:00:00], "Nachts")

      {:ok, event} = Daily.log_event(potty(%{occurred_at: at(~T[00:10:00])}), actor: lukas)

      assert [%{id: id}] = Daily.list_events_on!(@today, actor: lukas)
      assert id == event.id
      assert Daily.list_events_on!(@yesterday, actor: lukas) == []

      today_occ = occurrence(lukas, ~T[00:00:00])
      assert today_occ.status == :done
      assert today_occ.event_id == event.id
      assert occurrence(lukas, @yesterday, ~T[00:00:00]).status == :open
    end

    test "meal event links to a meal routine already ticked by hand, keeping its time",
         %{lukas: lukas, riv: riv} do
      meal = routine_since(lukas, @today, :meal, ~T[08:00:00], "Futter")
      :ok = Daily.ensure_day(@today)

      occ =
        Daily.list_occurrences_on!(@today, actor: lukas)
        |> Enum.find(&(&1.routine_id == meal.id))

      {:ok, ticked} =
        Daily.complete_occurrence(occ, %{done_at: at(~T[08:02:00])}, actor: riv)

      {:ok, event} = Daily.log_event(%{kind: :meal, occurred_at: at(~T[08:10:00])}, actor: lukas)

      linked = Daily.get_occurrence!(occ.id, actor: lukas)
      assert linked.event_id == event.id
      assert linked.status == :done
      assert linked.done_at == ticked.done_at
      assert linked.deviation_minutes == 2
      assert linked.completed_by_id == riv.id

      # deleting the event keeps the tick, only the link goes
      :ok = Daily.delete_event(event, actor: lukas)

      kept = Daily.get_occurrence!(occ.id, actor: lukas)
      assert kept.status == :done
      assert kept.event_id == nil
      assert kept.done_at == ticked.done_at
    end

    test "a hand tick at exactly the event's time stays when the event is deleted",
         %{lukas: lukas, riv: riv} do
      occ = meal_ticked_by_hand(lukas, riv, ~T[08:00:00])

      {:ok, event} = Daily.log_event(%{kind: :meal, occurred_at: at(~T[08:00:00])}, actor: lukas)
      assert event.link_mode == :attached
      assert Daily.get_occurrence!(occ.id, actor: lukas).event_id == event.id

      :ok = Daily.delete_event(event, actor: lukas)

      kept = Daily.get_occurrence!(occ.id, actor: lukas)
      assert kept.status == :done
      assert kept.event_id == nil
      assert kept.done_at == occ.done_at
      assert kept.completed_by_id == riv.id
    end

    test "updating an event attached to a hand tick keeps the tick", %{lukas: lukas, riv: riv} do
      occ = meal_ticked_by_hand(lukas, riv, ~T[08:00:00])
      {:ok, event} = Daily.log_event(%{kind: :meal, occurred_at: at(~T[08:00:00])}, actor: lukas)

      {:ok, event} = Daily.update_event(event, %{note: "Nassfutter"}, actor: lukas)
      assert event.link_mode == :attached

      kept = Daily.get_occurrence!(occ.id, actor: lukas)
      assert kept.event_id == event.id
      assert {kept.status, kept.done_at, kept.completed_by_id} == {:done, occ.done_at, riv.id}

      # moved away from the routine: the link goes, the tick stays
      {:ok, event} = Daily.update_event(event, %{occurred_at: at(~T[11:00:00])}, actor: lukas)
      assert event.link_mode == nil

      kept = Daily.get_occurrence!(occ.id, actor: lukas)
      assert kept.event_id == nil
      assert {kept.status, kept.done_at, kept.completed_by_id} == {:done, occ.done_at, riv.id}
    end

    test "requires a signed in user" do
      assert {:error, %Ash.Error.Forbidden{}} =
               Daily.log_event(potty(%{occurred_at: at(~T[10:00:00])}))
    end
  end

  describe "update and delete" do
    test "deleting the event reopens the routine", %{lukas: lukas} do
      {:ok, event} = Daily.log_event(potty(%{occurred_at: at(~T[10:10:00])}), actor: lukas)
      assert occurrence(lukas, ~T[10:00:00]).status == :done

      :ok = Daily.delete_event(event, actor: lukas)

      occ = occurrence(lukas, ~T[10:00:00])
      assert occ.status == :open
      assert occ.event_id == nil
      assert occ.done_at == nil
      assert Daily.list_events_on!(@today, actor: lukas) == []
    end

    test "changing the event time relinks", %{lukas: lukas} do
      {:ok, event} = Daily.log_event(potty(%{occurred_at: at(~T[10:10:00])}), actor: lukas)

      {:ok, updated} =
        Daily.update_event(event, %{occurred_at: at(~T[12:05:00])}, actor: lukas)

      assert occurrence(lukas, ~T[10:00:00]).status == :open

      occ = occurrence(lukas, ~T[12:00:00])
      assert occ.status == :done
      assert occ.event_id == updated.id
      assert occ.deviation_minutes == 5
    end

    test "updating keeps the link to the same routine with the new time", %{lukas: lukas} do
      {:ok, event} = Daily.log_event(potty(%{occurred_at: at(~T[10:10:00])}), actor: lukas)
      occ_1000 = occurrence(lukas, ~T[10:00:00])

      {:ok, _} =
        Daily.update_event(event, %{occurred_at: at(~T[10:30:00]), routine: occ_1000.id},
          actor: lukas
        )

      occ = occurrence(lukas, ~T[10:00:00])
      assert occ.status == :done
      assert occ.event_id == event.id
      assert occ.deviation_minutes == 30
    end

    test "turning the event into an accident reopens the routine", %{lukas: lukas} do
      {:ok, event} = Daily.log_event(potty(%{occurred_at: at(~T[10:10:00])}), actor: lukas)

      {:ok, _} = Daily.update_event(event, %{location: :inside}, actor: lukas)

      assert occurrence(lukas, ~T[10:00:00]).status == :open
    end
  end

  describe "validations" do
    test "potty needs a location and pee, poo or nothing", %{lukas: lukas} do
      assert {:error, error} =
               Daily.log_event(%{kind: :potty, location: :outside}, actor: lukas)

      assert errors_on(error, :pee) == ["Bitte Pipi, Kaka oder nichts wählen"]

      assert {:error, error} = Daily.log_event(%{kind: :potty, pee: true}, actor: lukas)
      assert errors_on(error, :location) != []
    end

    test "nothing excludes pee and poo and requires outside", %{lukas: lukas} do
      assert {:error, error} =
               Daily.log_event(
                 %{kind: :potty, nothing: true, pee: true, location: :outside},
                 actor: lukas
               )

      assert errors_on(error, :nothing) != []

      assert {:error, error} =
               Daily.log_event(%{kind: :potty, nothing: true, location: :inside}, actor: lukas)

      assert errors_on(error, :location) != []
    end

    test "other needs a name", %{lukas: lukas} do
      assert {:error, error} = Daily.log_event(%{kind: :other}, actor: lukas)
      assert errors_on(error, :name) != []

      assert {:ok, event} = Daily.log_event(%{kind: :other, name: "  Tierarzt "}, actor: lukas)
      assert event.name == "Tierarzt"
    end

    test "non-potty kinds ignore pee, poo, nothing and location", %{lukas: lukas} do
      {:ok, event} =
        Daily.log_event(
          %{kind: :walk, pee: true, poo: true, nothing: true, location: :inside},
          actor: lukas
        )

      assert %{pee: false, poo: false, nothing: false, location: nil} = event
    end

    test "occurred_at defaults to now", %{lukas: lukas} do
      {:ok, event} = Daily.log_event(%{kind: :play}, actor: lukas)
      assert DateTime.compare(event.occurred_at, Clock.utc_now()) == :eq
    end
  end

  describe "reading" do
    test "list_events_on sorts newest first, list_events_between spans days", %{lukas: lukas} do
      {:ok, a} = Daily.log_event(%{kind: :play, occurred_at: at(~T[09:00:00])}, actor: lukas)
      {:ok, b} = Daily.log_event(%{kind: :walk, occurred_at: at(~T[11:00:00])}, actor: lukas)

      {:ok, c} =
        Daily.log_event(%{kind: :sleep, occurred_at: at(@yesterday, ~T[23:30:00])},
          actor: lukas
        )

      assert Daily.list_events_on!(@today, actor: lukas) |> Enum.map(& &1.id) == [b.id, a.id]

      assert Daily.list_events_between!(@yesterday, @today, actor: lukas)
             |> Enum.map(& &1.id)
             |> Enum.sort() == Enum.sort([a.id, b.id, c.id])

      assert Daily.list_events_between!(@yesterday, @yesterday, actor: lukas)
             |> Enum.map(& &1.id) == [c.id]

      assert Daily.get_event!(a.id, actor: lukas).kind == :play
    end

    test "match_preview shows the automatic match and the candidates", %{lukas: lukas} do
      occ_1000 = occurrence(lukas, ~T[10:00:00])
      occ_1200 = occurrence(lukas, ~T[12:00:00])

      preview =
        Daily.match_preview(
          %{kind: :potty, location: :outside, occurred_at: at(~T[10:10:00])},
          actor: lukas
        )

      assert preview.auto.id == occ_1000.id
      assert Enum.map(preview.candidates, & &1.id) == [occ_1000.id, occ_1200.id]

      preview =
        Daily.match_preview(
          %{kind: :potty, location: :outside, occurred_at: at(~T[11:10:00])},
          actor: lukas
        )

      assert preview.auto == nil
      assert Enum.map(preview.candidates, & &1.id) == [occ_1200.id, occ_1000.id]

      assert %{auto: nil, candidates: []} =
               Daily.match_preview(
                 %{kind: :potty, location: :inside, occurred_at: at(~T[10:00:00])},
                 actor: lukas
               )

      # plans the day first
      assert %{auto: %{date: @yesterday}} =
               Daily.match_preview(
                 %{kind: :potty, location: :outside, occurred_at: at(@yesterday, ~T[10:00:00])},
                 actor: lukas
               )
    end

    test "recent_other_names lists up to 5 distinct names, latest first", %{lukas: lukas} do
      names = ~w(Tierarzt Bürsten Krallen Tierarzt Baden Welpenschule Autofahrt)

      names
      |> Enum.with_index()
      |> Enum.each(fn {name, minute} ->
        {:ok, _} =
          Daily.log_event(
            %{kind: :other, name: name, occurred_at: at(Time.new!(9, minute, 0))},
            actor: lukas
          )
      end)

      {:ok, _} = Daily.log_event(%{kind: :play, name: "Ball"}, actor: lukas)

      assert Daily.recent_other_names(actor: lukas) ==
               ~w(Autofahrt Welpenschule Baden Tierarzt Krallen)
    end
  end
end
