defmodule PuppyLogWeb.HealthLive do
  @moduledoc """
  Health tab „Gesundheit“ (docs/design/Gesundheit.dc.html): the next open
  appointment, the weight card and the list of vaccinations and care items,
  with a bottom sheet to mark an entry done (`/health/:id/done`).
  """

  use PuppyLogWeb, :live_view

  import Cinder.Refresh
  import PuppyLogWeb.HealthRow

  alias PuppyLog.{Clock, Puppy}
  alias PuppyLog.Puppy.{HealthEntry, HealthStatus, Weight}
  alias PuppyLogWeb.WeightChart

  on_mount {PuppyLogWeb.LiveUserAuth, :live_user_required}

  @collection "health-entries"
  @gone "Diesen Eintrag gibt es nicht mehr."
  @already_done "Schon erledigt"

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      for topic <- ~w(puppy_profile:changed weight_entries:changed health_entries:changed),
          do: PuppyLogWeb.Endpoint.subscribe(topic)
    end

    {:ok,
     socket
     |> assign(
       page_title: "Gesundheit",
       completing: nil,
       query: Ash.Query.for_read(HealthEntry, :overview)
     )
     |> load()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :complete, %{"id" => id}) do
    case Puppy.get_health_entry(id, actor: socket.assigns.current_user) do
      {:ok, %{status: :open} = entry} ->
        assign(socket, completing: entry, complete_form: complete_form(entry))

      {:ok, _done} ->
        close_sheet(socket, @already_done)

      {:error, _} ->
        close_sheet(socket, @gone)
    end
  end

  defp apply_action(socket, _action, _params), do: assign(socket, completing: nil)

  defp complete_form(entry) do
    to_form(%{"done_on" => Date.to_iso8601(Clock.today()), "batch" => entry.batch},
      as: :complete
    )
  end

  defp close_sheet(socket, message) do
    socket
    |> assign(completing: nil)
    |> put_flash(:error, message)
    |> push_patch(to: ~p"/health")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} tab={:health}>
      <.page_title title="Gesundheit" subtitle="Impfungen, Vorsorge und Gewicht" />

      <.next_card entry={@next} now={@now} today={@today} current_user={@current_user} />

      <.card id="weight-card">
        <div class="flex items-center justify-between">
          <h2 class="text-[13px] font-medium text-muted">Gewicht</h2>
          <.link
            navigate={~p"/weight/new"}
            class="-my-2 flex min-h-11 items-center text-[14px] font-semibold text-accent"
          >
            Wiegen eintragen
          </.link>
        </div>
        <.link navigate={~p"/weight"} class="block" aria-label="Alle Gewichtseinträge anzeigen">
          <div :if={@summary.latest} class="mt-0.5 flex flex-wrap items-baseline gap-x-2">
            <span class="font-display text-[28px] leading-[34px] font-semibold">
              {Weight.to_kg_string(@summary.latest.weight_grams)} kg
            </span>
            <span :if={@summary.change_grams} class="text-[13px] text-muted">
              {Weight.format_delta(@summary.change_grams)} seit {Format.short_date(
                @summary.previous.measured_on
              )}
            </span>
          </div>
          <p :if={!@summary.latest} class="py-4 text-[14px] text-muted">
            Noch nicht gewogen.
          </p>
          <div :if={@summary.latest} class="mt-2">
            <WeightChart.chart entries={@weights} birth_date={@profile && @profile.birth_date} />
          </div>
        </.link>
      </.card>

      <div class="flex items-center justify-between pt-1">
        <.section_label>Impfungen und Vorsorge</.section_label>
        <.link
          navigate={new_path()}
          class="-my-2 flex min-h-11 items-center px-1 text-[14px] font-semibold text-accent"
        >
          Termin eintragen
        </.link>
      </div>

      <Cinder.collection
        id="health-entries"
        query={@query}
        actor={@current_user}
        layout={:list}
        search={false}
        show_filters={false}
        query_opts={[load: [:previous]]}
      >
        <:item :let={entry}>
          <.health_row entry={entry} now={@now} today={@today} />
        </:item>
        <:empty>
          <div class="flex flex-col items-center gap-2 py-2">
            <span class="grid size-12 place-items-center rounded-full bg-mist text-muted">
              <.pl_icon name="heart" />
            </span>
            <p class="font-semibold text-ink">Noch nichts eingetragen</p>
            <p class="text-[14px]">
              Impfungen, Entwurmung und Tierarzttermine, mit Erinnerung ein paar Tage vorher.
            </p>
          </div>
        </:empty>
      </Cinder.collection>

      <p :if={@has_entries?} class="text-center text-[12.5px] text-muted">
        Nach links wischen: erledigt · Antippen: Details
      </p>
    </Layouts.app>

    <.sheet :if={@completing} id="health-sheet" title={@completing.title} close={~p"/health"}>
      <p class="-mt-2 text-[14px] text-muted">
        {kind_label(@completing.kind)} · fällig {Format.short_date(@completing.due_on)}
      </p>
      <.form
        for={@complete_form}
        id="health-complete-form"
        phx-submit="complete"
        class="flex flex-col gap-3.5"
      >
        <.input field={@complete_form[:done_on]} type="date" label="Wann" max={@today} />
        <.input
          :if={@completing.kind == :vaccination}
          field={@complete_form[:batch]}
          label="Impfstoff/Charge"
          autocomplete="off"
          placeholder="Optional, vom Aufkleber im Impfpass"
        />
        <.action_button type="submit" phx-disable-with="Speichert …">
          <.pl_icon name="check" class="size-5" /> Erledigt
        </.action_button>
      </.form>
    </.sheet>
    """
  end

  attr :entry, :any, required: true
  attr :now, DateTime, required: true
  attr :today, Date, required: true
  attr :current_user, :any, required: true

  defp next_card(%{entry: nil} = assigns) do
    ~H"""
    <.card id="health-next" class="flex items-center gap-3.5 !border-0 !bg-accent-tint">
      <span class="grid size-12 shrink-0 place-items-center rounded-xl bg-card text-accent">
        <.pl_icon name="check" />
      </span>
      <div class="min-w-0 flex-1">
        <p class="font-semibold">Keine offenen Termine</p>
        <.link
          navigate={new_path()}
          class="-my-1 inline-flex min-h-9 items-center text-[14px] font-semibold text-accent-dark underline-offset-2 hover:underline"
        >
          Termin eintragen
        </.link>
      </div>
    </.card>
    """
  end

  defp next_card(assigns) do
    state = HealthStatus.state(assigns.entry, assigns.now)

    assigns =
      assign(assigns,
        overdue?: state == :overdue,
        relative: relative(state, HealthStatus.days_until(assigns.entry, assigns.today)),
        details: details(assigns.entry)
      )

    ~H"""
    <.link navigate={entry_path(@entry)} class="block transition active:scale-[0.99]">
      <.card id="health-next" class="flex items-center gap-3.5 !border-0 !bg-accent-tint">
        <div
          class="flex h-14 w-12 shrink-0 flex-col items-center justify-center rounded-xl bg-card"
          aria-hidden="true"
        >
          <span class="text-[11px] leading-[14px] font-semibold uppercase text-danger">
            {Format.month_short(@entry.due_on)}
          </span>
          <span class="font-display text-[22px] leading-[26px] font-semibold">
            {@entry.due_on.day}
          </span>
        </div>
        <div class="min-w-0 flex-1">
          <p class="text-[12.5px] leading-4 font-semibold text-accent-dark">
            Nächster Termin · <span class={@overdue? && "text-danger"}>{@relative}</span>
          </p>
          <p class="truncate text-[16px] leading-[22px] font-semibold">
            <span class="sr-only">{kind_label(@entry.kind)}: </span>{@entry.title}
          </p>
          <p class="truncate text-[13px] leading-[18px] text-ink/75">{@details}</p>
          <p :if={@entry.assignee} class="text-[13px] leading-[18px] text-ink/75">
            Geht hin: {Format.who(@entry.assignee, @current_user)}
          </p>
        </div>
      </.card>
    </.link>
    """
  end

  defp relative(:due_today, _days), do: "heute"
  defp relative(:overdue, 0), do: "überfällig"
  defp relative(:overdue, -1), do: "seit 1 Tag überfällig"
  defp relative(:overdue, days), do: "seit #{-days} Tagen überfällig"
  defp relative(_state, days), do: in_days(days)

  defp details(entry) do
    time = entry.due_time && Calendar.strftime(entry.due_time, "%H:%M")

    [Format.short_date(entry.due_on), PuppyLogWeb.HealthRow.age(entry), time, entry.location]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  @impl true
  def handle_event("complete", %{"complete" => params}, socket) do
    entry = socket.assigns.completing
    attrs = %{done_on: params["done_on"], batch: blank_to_nil(params["batch"])}

    case Puppy.complete_health_entry(entry, attrs, actor: socket.assigns.current_user) do
      {:ok, done} ->
        socket = load(socket)

        {:noreply,
         socket
         |> put_flash(:info, completed_message(socket.assigns.entries, done))
         |> push_patch(to: ~p"/health")}

      {:error, error} ->
        {:noreply,
         socket
         |> put_flash(:error, error_message(error))
         |> assign(complete_form: to_form(params, as: :complete))}
    end
  end

  def handle_event("reopen", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    with {:ok, entry} <- Puppy.get_health_entry(id, actor: actor),
         {:ok, _open} <- Puppy.reopen_health_entry(entry, actor: actor) do
      {:noreply,
       socket |> put_flash(:info, "Wieder offen.") |> load() |> refresh_table(@collection)}
    else
      {:error, error} -> {:noreply, put_flash(socket, :error, error_message(error))}
    end
  end

  defp completed_message(entries, done) do
    case Enum.find(entries, &(&1.previous_id == done.id and &1.status == :open)) do
      nil -> "Erledigt."
      successor -> "Erledigt. Nächster Termin am #{Format.long_date(successor.due_on)}."
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  # The domain's own messages are German; anything else gets a generic hint.
  defp error_message(%{errors: errors}) when is_list(errors) and errors != [] do
    errors
    |> Enum.flat_map(&messages/1)
    |> case do
      [] -> generic_error()
      messages -> messages |> Enum.uniq() |> Enum.join(". ")
    end
  end

  defp error_message(_error), do: generic_error()

  defp messages(%{errors: errors}) when is_list(errors), do: Enum.flat_map(errors, &messages/1)

  defp messages(%{field: field, message: message}) when is_atom(field) and is_binary(message),
    do: [message]

  defp messages(_error), do: []

  defp generic_error, do: "Das hat leider nicht geklappt. Bitte noch einmal versuchen."

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "health_entries:changed"}, socket) do
    {:noreply,
     socket |> load() |> refresh_completing() |> refresh_table(@collection, silent: true)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{}, socket), do: {:noreply, load(socket)}

  # Another member may have finished or deleted the entry while the sheet is open.
  defp refresh_completing(%{assigns: %{completing: %HealthEntry{id: id}}} = socket) do
    case Puppy.get_health_entry(id, actor: socket.assigns.current_user) do
      {:ok, %{status: :open} = entry} -> assign(socket, completing: entry)
      {:ok, _done} -> close_sheet(socket, @already_done)
      {:error, _} -> close_sheet(socket, @gone)
    end
  end

  defp refresh_completing(socket), do: socket

  defp load(socket) do
    actor = socket.assigns.current_user
    entries = Puppy.list_health_entries!(actor: actor, load: [:assignee])
    now = Clock.now()

    assign(socket,
      profile: Puppy.get_profile!(actor: actor),
      summary: Puppy.weight_summary(actor: actor),
      weights: Puppy.list_weights!(actor: actor),
      entries: entries,
      has_entries?: entries != [],
      next: next_entry(entries, now),
      now: now,
      today: Clock.today()
    )
  end

  # Open entries come by due date; an overdue one goes before anything still ahead.
  defp next_entry(entries, now) do
    open = Enum.filter(entries, &(&1.status == :open))
    Enum.find(open, &(HealthStatus.state(&1, now) == :overdue)) || List.first(open)
  end
end
