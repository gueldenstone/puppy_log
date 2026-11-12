defmodule PuppyLogWeb.WeightLive do
  @moduledoc """
  Weight curve and history (entwuerfe/04) with a bottom sheet to add or
  correct a weighing (entwuerfe/05).
  """

  use PuppyLogWeb, :live_view

  import Cinder.Refresh

  alias AshPhoenix.Form
  alias PuppyLog.{Clock, Puppy}
  alias PuppyLog.Puppy.{Weight, WeightEntry}
  alias PuppyLogWeb.WeightChart

  on_mount {PuppyLogWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PuppyLogWeb.Endpoint.subscribe("weight_entries:changed")
      PuppyLogWeb.Endpoint.subscribe("puppy_profile:changed")
    end

    {:ok, socket |> assign(page_title: "Gewicht", form: nil) |> load()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params), do: assign(socket, form: nil, editing: nil)

  defp apply_action(socket, :new, _params) do
    form =
      Form.for_create(WeightEntry, :create,
        actor: socket.assigns.current_user,
        domain: Puppy,
        params: %{"measured_on" => Date.to_iso8601(Clock.today())}
      )

    assign(socket, form: to_form(form), editing: nil)
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    case Puppy.get_weight(id, actor: socket.assigns.current_user) do
      {:ok, entry} ->
        form =
          Form.for_update(entry, :update,
            actor: socket.assigns.current_user,
            domain: Puppy,
            params: %{"weight_kg" => Weight.to_kg_string(entry.weight_grams)}
          )

        assign(socket, form: to_form(form), editing: entry)

      {:error, _} ->
        socket
        |> put_flash(:error, "Diesen Eintrag gibt es nicht mehr.")
        |> push_patch(to: ~p"/gewicht")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.top_bar title="Gewicht" back={~p"/gesundheit"} />

      <.card>
        <div :if={@summary.latest} class="flex flex-wrap items-baseline gap-x-2">
          <span class="font-display text-[28px] leading-[34px] font-semibold">
            {Weight.to_kg_string(@summary.latest.weight_grams)} kg
          </span>
          <span :if={@summary.change_grams} class="text-[13px] text-muted">
            {Weight.format_delta(@summary.change_grams)} seit {Format.short_date(
              @summary.previous.measured_on
            )}
          </span>
        </div>
        <div class={@summary.latest && "mt-2"}>
          <WeightChart.chart entries={@entries} birth_date={@profile && @profile.birth_date} />
        </div>
        <p
          :if={@summary.latest && !(@profile && @profile.birth_date)}
          class="mt-2 text-[12.5px] text-muted"
        >
          Mit Geburtsdatum im Profil zeigt die Kurve Lebenswochen.
        </p>
      </.card>

      <.section_label class="pt-1">Einträge</.section_label>

      <Cinder.collection
        id="weights"
        query={Ash.Query.for_read(WeightEntry, :history)}
        actor={@current_user}
        layout={:list}
        page_size={50}
        search={false}
        show_filters={false}
        query_opts={[load: [:created_by]]}
      >
        <:item :let={entry}>
          <.swipe_row id={"weight-#{entry.id}"}>
            <.link
              patch={~p"/gewicht/#{entry.id}"}
              class="flex min-h-14 items-center gap-3 px-4 py-2"
              aria-label={"#{Format.short_date(entry.measured_on)}, #{Weight.to_kg_string(entry.weight_grams)} kg, ändern"}
            >
              <div class="min-w-0 flex-1">
                <p class="font-medium">{Format.relative_day(entry.measured_on, @today)}</p>
                <p class="truncate text-[12.5px] text-muted">
                  {Format.who(entry.created_by, @current_user)}<span :if={entry.note}> · {entry.note}</span>
                </p>
              </div>
              <div class="text-right">
                <p class="font-medium tabular-nums">{Weight.to_kg_string(entry.weight_grams)} kg</p>
                <p :if={@deltas[entry.id]} class="text-[12.5px] tabular-nums text-muted">
                  {Weight.format_delta(@deltas[entry.id])}
                </p>
              </div>
            </.link>
            <:actions>
              <.swipe_action
                icon="edit"
                type="button"
                phx-click={JS.patch(~p"/gewicht/#{entry.id}")}
              >
                Ändern
              </.swipe_action>
              <.swipe_action
                kind={:danger}
                icon="trash"
                type="button"
                phx-click="delete"
                phx-value-id={entry.id}
                data-confirm="Diesen Eintrag löschen?"
              >
                Löschen
              </.swipe_action>
            </:actions>
          </.swipe_row>
        </:item>
        <:empty>
          <div class="flex flex-col items-center gap-2 py-2">
            <span class="grid size-12 place-items-center rounded-full bg-mist text-muted">
              <.pl_icon name="scale" />
            </span>
            <p class="font-semibold text-ink">Noch kein Eintrag</p>
            <p class="text-[14px]">Wiegt euren Welpen am besten einmal pro Woche.</p>
          </div>
        </:empty>
      </Cinder.collection>

      <p :if={@entries != []} class="text-center text-[12.5px] text-muted">
        Nach links wischen oder lange drücken zum Ändern oder Löschen.
      </p>

      <:footer>
        <.action_button patch={~p"/gewicht/neu"}>
          <.pl_icon name="plus" class="size-5" /> Wiegen eintragen
        </.action_button>
      </:footer>
    </Layouts.app>

    <.sheet
      :if={@form}
      id="weight-sheet"
      title={if @editing, do: "Gewicht ändern", else: "Wiegen eintragen"}
      close={~p"/gewicht"}
    >
      <.form
        for={@form}
        id="weight-form"
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col gap-3.5"
      >
        <div class="flex flex-col gap-1.5">
          <.input
            field={@form[:weight_kg]}
            label="Gewicht in kg"
            inputmode="decimal"
            autocomplete="off"
            enterkeyhint="done"
            placeholder="0,0"
            phx-mounted={JS.focus()}
            class="h-[72px] w-full rounded-xl border border-field bg-card px-3.5 text-center font-display text-[40px] font-semibold tabular-nums outline-none transition focus:border-accent focus:ring-4 focus:ring-accent/15"
          />
          <p :if={@hint} class="text-center text-[12.5px] text-muted">{@hint}</p>
        </div>
        <.input field={@form[:measured_on]} type="date" label="Datum" max={@today} />
        <.input
          field={@form[:note]}
          label="Notiz"
          placeholder="Optional, zum Beispiel vor dem Fressen"
        />
        <.action_button type="submit" phx-disable-with="Speichert …">Speichern</.action_button>
      </.form>
    </.sheet>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    form = Form.validate(socket.assigns.form, params)
    {:noreply, socket |> assign(form: form) |> assign_hint(params)}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case Form.submit(socket.assigns.form, params: params) do
      {:ok, entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{Weight.to_kg_string(entry.weight_grams)} kg gespeichert.")
         |> push_patch(to: ~p"/gewicht")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    actor = socket.assigns.current_user

    with {:ok, entry} <- Puppy.get_weight(id, actor: actor),
         :ok <- Puppy.delete_weight(entry, actor: actor) do
      {:noreply, put_flash(socket, :info, "Eintrag gelöscht.")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Löschen hat nicht geklappt.")}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{topic: "weight_entries:changed"}, socket) do
    {:noreply, socket |> load() |> refresh_table("weights", silent: true)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{}, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    actor = socket.assigns.current_user
    entries = Puppy.list_weights!(actor: actor)

    assign(socket,
      profile: Puppy.get_profile!(actor: actor),
      summary: Puppy.weight_summary(actor: actor),
      entries: entries,
      deltas: deltas(entries),
      today: Clock.today(),
      hint: nil
    )
  end

  # change of every entry relative to the one before it (entries are newest first)
  defp deltas(entries) do
    entries
    |> Enum.chunk_every(2, 1, :discard)
    |> Map.new(fn [newer, older] -> {newer.id, newer.weight_grams - older.weight_grams} end)
  end

  defp assign_hint(socket, %{"weight_kg" => input}) do
    hint =
      with {:ok, grams} <- Weight.parse_kg(input),
           %{latest: %{} = latest} <- socket.assigns.summary,
           true <- is_nil(socket.assigns.editing) or socket.assigns.editing.id != latest.id do
        "#{Weight.format_delta(grams - latest.weight_grams)} seit dem letzten Mal (#{Format.short_date(latest.measured_on)})"
      else
        _ -> nil
      end

    assign(socket, hint: hint)
  end

  defp assign_hint(socket, _params), do: socket
end
