defmodule PuppyLogWeb.RoutineRow do
  @moduledoc """
  One planned routine in a day list (entwuerfe/01): round check, title, state
  line, planned time and assignee, swipe left to skip or reopen.

  The parent LiveView handles the events `"complete"` (tick off now),
  `"skip"` and `"reopen"`, each with `phx-value-id` set to the occurrence id.
  The check ticks off right away only for open routines that are not Lösen
  and not from a past day; otherwise it opens the sheet at `sheet_path`.
  """

  use Phoenix.Component

  import PuppyLogWeb.UI

  alias PuppyLog.Clock
  alias PuppyLog.Daily.Matching
  alias PuppyLogWeb.Format

  attr :occurrence, :any, required: true, doc: "with `completed_by` and `assignee` loaded"
  attr :now, NaiveDateTime, required: true, doc: "local wall-clock time"
  attr :current_user, :any, required: true
  attr :sheet_path, :string, required: true

  def routine_row(assigns) do
    occurrence = assigns.occurrence
    state = Matching.state(occurrence, assigns.now)

    assigns =
      assign(assigns,
        state: state,
        quick?: state in [:open, :overdue] and occurrence.kind != :potty,
        late: late_minutes(occurrence)
      )

    ~H"""
    <.swipe_row id={"routine-#{@occurrence.id}"}>
      <div class="flex min-h-14 items-center gap-1 py-1 pr-4 pl-1.5">
        <button
          :if={@quick?}
          type="button"
          phx-click="complete"
          phx-value-id={@occurrence.id}
          aria-label={"Abhaken: #{@occurrence.name}"}
          class="group grid size-11 shrink-0 place-items-center rounded-full"
        >
          <.check state={@state} />
        </button>
        <.link
          :if={!@quick?}
          patch={@sheet_path}
          aria-label={check_label(@state, @occurrence.name)}
          class="group grid size-11 shrink-0 place-items-center rounded-full"
        >
          <.check state={@state} />
        </.link>

        <.link patch={@sheet_path} class="flex min-w-0 flex-1 items-center gap-3 py-1.5">
          <div class="min-w-0 flex-1">
            <p class={[
              "truncate text-[15px] leading-5 font-medium",
              @state == :skipped && "text-muted"
            ]}>
              {@occurrence.name}
            </p>
            <p class={[
              "flex items-center gap-1.5 text-[12.5px] leading-[17px]",
              if(@state in [:overdue, :missed],
                do: "font-semibold text-danger",
                else: "text-muted"
              )
            ]}>
              <span class="truncate">{meta(@occurrence, @state, @now, @current_user)}</span>
              <.chip :if={@late} kind={:warn} class="!py-0 tabular-nums">{@late}</.chip>
            </p>
          </div>
          <div class="flex shrink-0 items-center gap-2">
            <span class="text-[13px] tabular-nums text-muted">{hhmm(@occurrence.planned_start)}</span>
            <span
              :if={@occurrence.assignee}
              class={[
                "grid size-6 place-items-center rounded-full text-[10px] font-semibold text-white",
                if(@occurrence.assignee.id == @current_user.id, do: "bg-accent", else: "bg-pipi")
              ]}
              title={"Zuständig: #{Format.who(@occurrence.assignee, @current_user)}"}
            >
              {Format.initials(@occurrence.assignee, @current_user)}
            </span>
          </div>
        </.link>
      </div>
      <:actions>
        <.swipe_action
          :if={@occurrence.status == :open}
          kind={:warn}
          icon="skip"
          type="button"
          phx-click="skip"
          phx-value-id={@occurrence.id}
        >
          Überspringen
        </.swipe_action>
        <.swipe_action
          :if={@occurrence.status != :open}
          icon="undo"
          type="button"
          phx-click="reopen"
          phx-value-id={@occurrence.id}
        >
          Wieder öffnen
        </.swipe_action>
      </:actions>
    </.swipe_row>
    """
  end

  attr :state, :atom, required: true

  defp check(%{state: :done} = assigns) do
    ~H"""
    <span class="grid size-7 place-items-center rounded-full border-2 border-accent bg-accent text-white transition group-active:scale-90">
      <.pl_icon name="check" class="size-4" stroke_width={3} />
    </span>
    """
  end

  defp check(%{state: :skipped} = assigns) do
    ~H"""
    <span class="grid size-7 place-items-center rounded-full border-2 border-mist bg-mist text-muted transition group-active:scale-90">
      <.pl_icon name="skip" class="size-3.5" stroke_width={2.5} />
    </span>
    """
  end

  defp check(assigns) do
    ~H"""
    <span class={[
      "block size-7 rounded-full border-2 bg-card transition group-hover:bg-accent-tint group-active:scale-90",
      if(@state in [:overdue, :missed], do: "border-danger", else: "border-unchecked")
    ]} />
    """
  end

  defp check_label(state, name) when state in [:done, :skipped], do: "Wieder öffnen: #{name}"
  defp check_label(_state, name), do: "Abhaken: #{name}"

  defp meta(occurrence, :done, _now, current_user) do
    local = Clock.local(occurrence.done_at)

    day =
      if DateTime.to_date(local) != occurrence.date,
        do: "#{Format.short_date(DateTime.to_date(local))}, "

    "Erledigt #{day}#{hhmm(local)}" <> by(occurrence, current_user)
  end

  defp meta(occurrence, :skipped, _now, current_user),
    do: "Übersprungen" <> by(occurrence, current_user)

  defp meta(occurrence, :overdue, now, _current_user) do
    due = NaiveDateTime.new!(occurrence.date, occurrence.planned_end || occurrence.planned_start)
    "Seit #{since(div(NaiveDateTime.diff(now, due, :second), 60))} fällig"
  end

  defp meta(_occurrence, :missed, _now, _current_user), do: "Nicht erledigt"

  defp meta(%{planned_end: nil} = occurrence, :open, _now, _current_user),
    do: "Um #{hhmm(occurrence.planned_start)}"

  defp meta(occurrence, :open, _now, _current_user),
    do: "#{hhmm(occurrence.planned_start)} bis #{hhmm(occurrence.planned_end)}"

  defp since(minutes) when minutes < 60, do: "#{minutes} Min"
  defp since(minutes), do: "#{div(minutes, 60)} Std"

  defp by(%{completed_by: %{} = user}, current_user), do: " · " <> Format.who(user, current_user)
  defp by(_occurrence, _current_user), do: ""

  # „+40 Min“ / „−20 Min“ for a routine done outside the tolerance
  defp late_minutes(%{status: :done, deviation_minutes: deviation}) when is_integer(deviation) do
    cond do
      Matching.kept?(deviation) -> nil
      deviation > 0 -> "+#{deviation} Min"
      true -> "−#{-deviation} Min"
    end
  end

  defp late_minutes(_occurrence), do: nil

  defp hhmm(time), do: Calendar.strftime(time, "%H:%M")
end
