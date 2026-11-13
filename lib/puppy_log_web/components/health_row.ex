defmodule PuppyLogWeb.HealthRow do
  @moduledoc """
  One health entry in the list „Impfungen und Vorsorge“ (docs/design/Gesundheit.dc.html):
  title, a line with date, repetition or batch, and a state chip. Tapping opens
  the entry (`/health/:id`); swiping left offers „Erledigt“ (patches to
  `/health/:id/done`) or, for done entries, „Wieder öffnen“.

  The parent LiveView handles the event `"reopen"` with `phx-value-id`.
  """

  use PuppyLogWeb, :html

  alias PuppyLog.Puppy.HealthStatus

  # chips further out than this show the date instead of a day count
  @max_count_days 30

  @kind_labels %{
    vaccination: "Impfung",
    deworming: "Entwurmung",
    flea_tick: "Floh/Zecke",
    other_care: "Andere Vorsorge",
    vet_visit: "Tierarzt"
  }

  @doc "German label of a health entry kind."
  def kind_label(kind), do: Map.fetch!(@kind_labels, kind)

  @doc "Path of the form for a new entry."
  def new_path, do: ~p"/health/new"

  @doc "Path of the form of an entry."
  def entry_path(%{id: id}), do: ~p"/health/#{id}"

  @doc ~S"""
  „in 3 Tagen“ for a number of days ahead.

      iex> PuppyLogWeb.HealthRow.in_days(1)
      "in 1 Tag"
      iex> PuppyLogWeb.HealthRow.in_days(7)
      "in 7 Tagen"
  """
  def in_days(1), do: "in 1 Tag"
  def in_days(days), do: "in #{days} Tagen"

  attr :entry, :any, required: true, doc: "with `previous` loaded"
  attr :now, DateTime, required: true
  attr :today, Date, required: true

  def health_row(assigns) do
    ~H"""
    <.swipe_row id={"health-#{@entry.id}"} width={96}>
      <.link navigate={entry_path(@entry)} class="flex min-h-14 items-center gap-3 px-4 py-2">
        <div class="min-w-0 flex-1">
          <p class="truncate text-[15px] leading-5 font-medium">
            <span class="sr-only">{kind_label(@entry.kind)}: </span>{@entry.title}
          </p>
          <p class="truncate text-[12.5px] leading-[17px] text-muted">
            {subtitle(@entry, @today)}
          </p>
        </div>
        <.health_chip entry={@entry} now={@now} today={@today} />
      </.link>
      <:actions>
        <.swipe_action
          :if={@entry.status == :open}
          icon="check"
          type="button"
          phx-click={JS.patch(~p"/health/#{@entry.id}/done")}
        >
          Erledigt
        </.swipe_action>
        <.swipe_action
          :if={@entry.status == :done}
          icon="undo"
          type="button"
          phx-click="reopen"
          phx-value-id={@entry.id}
        >
          Wieder öffnen
        </.swipe_action>
      </:actions>
    </.swipe_row>
    """
  end

  attr :entry, :any, required: true
  attr :now, DateTime, required: true
  attr :today, Date, required: true

  def health_chip(assigns) do
    {kind, label} =
      chip(assigns.entry, HealthStatus.state(assigns.entry, assigns.now), assigns.today)

    assigns = assign(assigns, kind: kind, label: label)

    ~H"""
    <.chip kind={@kind} class="shrink-0 tabular-nums">{@label}</.chip>
    """
  end

  defp chip(_entry, :done, _today), do: {:ok, "Erledigt"}
  defp chip(_entry, :due_today, _today), do: {:warn, "Heute"}
  defp chip(_entry, :overdue, _today), do: {:bad, "Überfällig"}

  defp chip(entry, :due_soon, today),
    do: {:warn, entry |> HealthStatus.days_until(today) |> in_days() |> capitalize()}

  defp chip(entry, :open, today) do
    case HealthStatus.days_until(entry, today) do
      days when days <= @max_count_days -> {:neutral, days |> in_days() |> capitalize()}
      _ -> {:neutral, Format.day_month_numeric(entry.due_on, today)}
    end
  end

  defp capitalize("in" <> rest), do: "In" <> rest

  defp subtitle(%{status: :done} = entry, today) do
    join([
      Format.day_month_numeric(entry.done_on || entry.due_on, today),
      entry.batch && "Charge #{entry.batch}"
    ])
  end

  defp subtitle(entry, today) do
    join([when_line(entry, today), repetition(entry.repeat_weeks), entry.location])
  end

  defp when_line(%{previous: %{status: :done, done_on: %Date{} = done_on}}, today),
    do: "Zuletzt #{Format.day_month_numeric(done_on, today)}"

  defp when_line(%{due_time: %Time{} = time} = entry, today),
    do: "#{Format.day_month_numeric(entry.due_on, today)}, #{Calendar.strftime(time, "%H:%M")}"

  defp when_line(entry, today), do: Format.day_month_numeric(entry.due_on, today)

  defp repetition(nil), do: nil
  defp repetition(1), do: "jede Woche"
  defp repetition(weeks), do: "alle #{weeks} Wochen"

  defp join(parts), do: parts |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
end
