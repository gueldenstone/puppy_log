defmodule PuppyLogWeb.EventForm do
  @moduledoc """
  Bottom sheet „Ereignis eintragen“ (docs/design/Eintragen.dc.html,
  entwuerfe/15): what happened, when, which routine it fulfils, and a note.

  Attributes: `id`, `current_user`, `return_to`, and optionally
  `event` (edit that event), `preset` (see `preset/1`) and `default_date`
  (a past day starts the time choice on „Uhrzeit“ at the current time of day
  on that day).

  The routine area follows `Daily.match_preview/2` live: an automatic match
  is shown as „Erfüllt: …“ (with „ändern“ for the choice list), otherwise
  the candidates of the day are offered with none preselected. When editing,
  the current link is sent explicitly so it is kept.

  After saving it patches to `return_to` with a flash.
  """

  use PuppyLogWeb, :live_component

  alias PuppyLog.{Clock, Daily}
  alias PuppyLog.Daily.{Matching, Occurrence}
  alias PuppyLogWeb.TimeChoice

  @kind_tiles [
    {:potty, "Lösen", "pipi"},
    {:meal, "Mahlzeit", "bowl"},
    {:walk, "Gassi", "gassi"},
    {:sleep, "Schlaf", "moon"},
    {:play, "Spiel", "ball"},
    {:vomit, "Erbrechen", "alert"},
    {:other, "Anderes", "plus"}
  ]
  @kinds Map.new(@kind_tiles, fn {kind, _label, _icon} -> {Atom.to_string(kind), kind} end)

  @potty_toggles [
    {"pee", :pee, "Pipi", "pipi"},
    {"poo", :poo, "Kaka", "kaka"},
    {"nothing", :nothing, "Nichts gemacht", "x"}
  ]
  @toggles Map.new(@potty_toggles, fn {param, field, _label, _icon} -> {param, field} end)

  @presets %{
    "pee" => %{kind: :potty, pee: true, location: :outside},
    "poo" => %{kind: :potty, poo: true, location: :outside},
    "meal" => %{kind: :meal},
    "walk" => %{kind: :walk}
  }

  @fields [:kind, :pee, :poo, :nothing, :location, :name, :note]
  @potty_fields [:pee, :poo, :nothing, :location]
  @placed_fields [:kind, :name, :note, :routine, :occurred_at | @potty_fields]
  @no_preview %{auto: nil, candidates: []}
  @future "Bitte eine Uhrzeit wählen, die nicht in der Zukunft liegt."
  @failed "Das hat leider nicht geklappt. Bitte noch einmal versuchen."

  @doc """
  The preset of a quick log button (`type` query parameter): `"pee"`,
  `"poo"`, `"meal"` or `"walk"`. Anything else gives no preset.
  """
  @spec preset(String.t() | nil) :: map
  def preset(type), do: Map.get(@presets, type, %{})

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:event, fn -> nil end)
      |> assign_new(:preset, fn -> %{} end)
      |> assign_new(:default_date, fn -> nil end)

    %{event: event, preset: preset, default_date: date} = socket.assigns
    key = {event && event.id, preset, date}

    socket = if socket.assigns[:key] == key, do: socket, else: reset(socket, key)
    {:ok, refresh_preview(socket)}
  end

  defp reset(socket, key) do
    actor = socket.assigns.current_user

    socket
    |> assign(key: key, errors: %{}, time_error: nil, expanded: false)
    |> assign(recent_names: Daily.recent_other_names(actor: actor))
    |> assign(initial_state(socket.assigns.event, socket.assigns, actor))
  end

  defp initial_state(nil, %{preset: preset, default_date: date}, _actor) do
    blank = %{
      kind: nil,
      pee: false,
      poo: false,
      nothing: false,
      location: nil,
      name: "",
      note: ""
    }

    blank
    |> Map.merge(Map.take(preset, @fields))
    |> Map.merge(initial_time(date))
    |> Map.merge(%{routine: nil, initial_custom: nil, own_occurrence: nil})
  end

  defp initial_state(event, _assigns, actor) do
    # kept in its own assign: the parent may re-render with the unloaded event
    own = Ash.load!(event, :occurrence, actor: actor).occurrence
    custom = TimeChoice.to_input(event.occurred_at)

    event
    |> Map.take(@fields)
    |> Map.update!(:name, &(&1 || ""))
    |> Map.update!(:note, &(&1 || ""))
    |> Map.merge(%{
      own_occurrence: own,
      choice: "custom",
      custom: custom,
      initial_custom: custom,
      # update_event defaults to "auto": send the current link explicitly
      routine: if(own, do: own.id, else: "none")
    })
  end

  defp initial_time(date) do
    now = Clock.now()

    if is_nil(date) or date == DateTime.to_date(now) do
      %{choice: "now", custom: TimeChoice.to_input(now)}
    else
      at = Clock.local_datetime(date, now |> DateTime.to_time() |> Time.truncate(:second))
      at = if DateTime.after?(at, now), do: now, else: at
      %{choice: "custom", custom: TimeChoice.to_input(at)}
    end
  end

  # -- routine preview

  defp refresh_preview(socket) do
    preview = preview(socket.assigns)
    ids = Enum.map(preview.candidates, & &1.id)

    routine =
      case socket.assigns.routine do
        choice when choice in [nil, "none"] -> choice
        id -> if id in ids, do: id
      end

    assign(socket, preview: preview, routine: routine)
  end

  defp preview(%{kind: nil}), do: @no_preview

  defp preview(assigns) do
    case occurred_at(assigns) do
      {:ok, at} ->
        event = %{kind: assigns.kind, location: if(assigns.kind == :potty, do: assigns.location)}

        event
        |> Map.merge(%{occurred_at: at, event_id: assigns.event && assigns.event.id})
        |> Daily.match_preview(actor: assigns.current_user)
        |> with_own_link(assigns.own_occurrence, event)

      :error ->
        @no_preview
    end
  end

  # An explicit link to an occurrence of another day stays choosable while it fits.
  defp with_own_link(preview, %Occurrence{} = own, event) do
    if Matching.fulfils?(own.kind, event) and
         not Enum.any?(preview.candidates, &(&1.id == own.id)),
       do: %{preview | candidates: preview.candidates ++ [own]},
       else: preview
  end

  defp with_own_link(preview, _own, _event), do: preview

  # An unchanged time of an edited event keeps its exact (sub-minute) value.
  defp occurred_at(%{
         event: %{occurred_at: at},
         choice: "custom",
         custom: same,
         initial_custom: same
       }),
       do: {:ok, at}

  defp occurred_at(assigns) do
    with {:ok, at} <- TimeChoice.resolve(assigns.choice, assigns.custom, Clock.now()) do
      {:ok, DateTime.shift_zone!(at, "Etc/UTC")}
    end
  end

  # -- render

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        kind_tiles: @kind_tiles,
        potty_toggles: @potty_toggles,
        options: TimeChoice.options(),
        potty_errors: Enum.flat_map(@potty_fields, &Map.get(assigns.errors, &1, [])),
        other_errors: Map.get(assigns.errors, :base, [])
      )

    ~H"""
    <div>
      <.sheet
        id={@id}
        title={if @event, do: "Eintrag bearbeiten", else: "Ereignis eintragen"}
        close={@return_to}
      >
        <form
          id={"#{@id}-form"}
          phx-change="change"
          phx-submit="save"
          phx-target={@myself}
          class="flex flex-col gap-4"
        >
          <section class="flex flex-col gap-2">
            <.section_label>Was ist passiert?</.section_label>
            <div class="grid grid-cols-4 gap-2" role="group" aria-label="Was ist passiert?">
              <button
                :for={{kind, label, icon} <- @kind_tiles}
                type="button"
                phx-click="kind"
                phx-value-kind={kind}
                phx-target={@myself}
                aria-pressed={to_string(@kind == kind)}
                class={[
                  "flex h-[76px] flex-col items-center justify-center gap-1 rounded-[14px] border-2 transition active:scale-95",
                  tile_class(kind, @kind == kind)
                ]}
              >
                <.pl_icon name={icon} class="size-6" />
                <span class="text-[12px] leading-4 font-semibold">{label}</span>
              </button>
            </div>
            <.field_errors errors={@errors[:kind]} />
          </section>

          <section :if={@kind == :potty} class="flex flex-col gap-2">
            <div class="grid grid-cols-3 gap-2" role="group" aria-label="Ergebnis">
              <button
                :for={{param, field, label, icon} <- @potty_toggles}
                type="button"
                phx-click="toggle"
                phx-value-field={param}
                phx-target={@myself}
                aria-pressed={to_string(Map.fetch!(assigns, field))}
                class={[
                  "flex h-14 items-center justify-center gap-1.5 rounded-xl border-2 text-[14px] font-semibold transition active:scale-95",
                  toggle_class(field, Map.fetch!(assigns, field))
                ]}
              >
                <.pl_icon name={icon} class="size-5" />
                {label}
              </button>
            </div>

            <.section_label class="pt-1">Wo?</.section_label>
            <div class="grid grid-cols-2 gap-2" role="group" aria-label="Wo?">
              <button
                type="button"
                phx-click="location"
                phx-value-location="outside"
                phx-target={@myself}
                aria-pressed={to_string(@location == :outside)}
                class={[location_class(:outside, @location == :outside)]}
              >
                Draußen
              </button>
              <button
                type="button"
                phx-click="location"
                phx-value-location="inside"
                phx-target={@myself}
                aria-pressed={to_string(@location == :inside)}
                disabled={@nothing}
                class={[location_class(:inside, @location == :inside)]}
              >
                Drinnen
              </button>
            </div>
            <p :if={@location} class="px-0.5 text-[12.5px] leading-[17px] text-muted">
              {if @location == :inside,
                do: "Wird als Unfall gezählt und erfüllt keine Routine.",
                else: "Zählt für die Stubenreinheit."}
            </p>
            <.field_errors errors={@potty_errors} />
          </section>

          <div :if={@kind == :other} class="flex flex-col gap-2">
            <.input
              name="name"
              id={"#{@id}-name"}
              label="Was genau?"
              value={@name}
              errors={@errors[:name] || []}
              placeholder="Zum Beispiel Zähne geputzt"
              maxlength="60"
              autocomplete="off"
            />
            <div
              :if={@recent_names != []}
              class="flex flex-wrap items-center gap-1.5 px-0.5 text-[12.5px] text-muted"
            >
              Zuletzt benutzt:
              <button
                :for={name <- @recent_names}
                type="button"
                phx-click="pick_name"
                phx-value-name={name}
                phx-target={@myself}
                class="min-h-8 rounded-[10px] bg-mist px-2.5 text-[12px] font-semibold text-muted transition hover:text-ink active:scale-95"
              >
                {name}
              </button>
            </div>
          </div>

          <section class="flex flex-col gap-2">
            <.section_label>Wann</.section_label>
            <div class="grid grid-cols-5 gap-1 rounded-xl bg-mist p-1" role="group" aria-label="Wann">
              <button
                :for={{label, value} <- @options}
                type="button"
                phx-click="choose"
                phx-value-choice={value}
                phx-target={@myself}
                aria-pressed={to_string(@choice == value)}
                class={[
                  "h-11 rounded-[9px] px-0.5 text-[13px] leading-4 font-semibold transition",
                  if(@choice == value,
                    do: "bg-card text-accent shadow-[0_1px_2px_rgba(20,32,27,0.15)]",
                    else: "text-muted hover:text-ink"
                  )
                ]}
              >
                {label}
              </button>
            </div>
            <.input
              :if={@choice == "custom"}
              type="datetime-local"
              name="custom"
              id={"#{@id}-custom"}
              label="Uhrzeit"
              value={@custom}
              max={TimeChoice.to_input(Clock.now())}
              errors={List.wrap(@time_error) ++ (@errors[:occurred_at] || [])}
            />
            <p
              :if={@time_error && @choice != "custom"}
              class="px-0.5 text-[12.5px] font-semibold text-danger"
            >
              {@time_error}
            </p>
          </section>

          <section
            :if={@preview.candidates != [] or @errors[:routine]}
            id={"#{@id}-routine"}
            class="flex flex-col gap-2"
          >
            <%= if summary?(@preview, @routine, @expanded) do %>
              <.card class="flex items-center gap-3 !py-2.5 !pr-2">
                <span class="grid size-8 shrink-0 place-items-center rounded-full bg-accent text-white">
                  <.pl_icon name="check" class="size-4" stroke_width="3" />
                </span>
                <p class="min-w-0 flex-1 text-[15px] font-medium">
                  Erfüllt: {@preview.auto.name} ({planned(@preview.auto)})
                </p>
                <button
                  type="button"
                  phx-click="expand"
                  phx-target={@myself}
                  class="min-h-11 rounded-lg px-2 text-[14px] font-semibold text-accent transition hover:bg-accent-tint"
                >
                  ändern
                </button>
              </.card>
            <% else %>
              <.section_label :if={@preview.candidates != []}>Routine abhaken?</.section_label>
              <.card :if={@preview.candidates != []} flush role="radiogroup" aria-label="Routine">
                <.routine_option
                  :for={occurrence <- @preview.candidates}
                  value={occurrence.id}
                  checked={checked_routine(@preview, @routine, @expanded) == occurrence.id}
                  label={occurrence.name}
                  meta={planned(occurrence)}
                />
                <.routine_option
                  value="none"
                  checked={@routine == "none"}
                  label="Keine"
                  meta="Keine Routine abhaken"
                />
              </.card>
            <% end %>
            <.field_errors errors={@errors[:routine]} />
          </section>

          <.input
            name="note"
            id={"#{@id}-note"}
            label="Notiz"
            value={@note}
            errors={@errors[:note] || []}
            placeholder="Optional"
            maxlength="500"
            autocomplete="off"
          />

          <p :if={!@event} class="-mt-2 px-0.5 text-[12.5px] leading-[17px] text-muted">
            Gespeichert wird, wer den Eintrag gemacht hat (du).
          </p>

          <.field_errors errors={@other_errors} />

          <.action_button type="submit" phx-disable-with="Speichern …">
            {if @event, do: "Speichern", else: "Eintragen"}
          </.action_button>
        </form>
      </.sheet>
    </div>
    """
  end

  attr :value, :string, required: true
  attr :checked, :boolean, required: true
  attr :label, :string, required: true
  attr :meta, :string, required: true

  defp routine_option(assigns) do
    ~H"""
    <label class="flex min-h-14 cursor-pointer items-center gap-3 border-t border-divider px-4 py-2 transition first:border-t-0 hover:bg-canvas has-checked:bg-accent-tint/40">
      <input
        type="radio"
        name="routine"
        value={@value}
        checked={@checked}
        class="size-5 shrink-0 accent-accent"
      />
      <span class="min-w-0 flex-1 text-[15px] leading-5 font-medium">{@label}</span>
      <span class="text-[12.5px] leading-[17px] text-muted tabular-nums">{@meta}</span>
    </label>
    """
  end

  attr :errors, :list, default: nil

  defp field_errors(assigns) do
    ~H"""
    <p
      :for={message <- @errors || []}
      class="px-0.5 text-[12.5px] leading-[17px] font-semibold text-danger"
    >
      {message}
    </p>
    """
  end

  defp tile_class(:potty, true), do: "border-pipi bg-pipi-tint text-pipi"
  defp tile_class(_kind, true), do: "border-accent bg-accent-tint text-accent"
  defp tile_class(_kind, false), do: "border-line bg-card text-ink hover:border-accent/40"

  defp toggle_class(:pee, true), do: "border-pipi bg-pipi-tint text-pipi"
  defp toggle_class(:poo, true), do: "border-kaka bg-kaka-tint text-kaka"
  defp toggle_class(:nothing, true), do: "border-accent bg-accent-tint text-accent"
  defp toggle_class(_field, false), do: "border-line bg-card text-ink hover:border-accent/40"

  defp location_class(location, selected?) do
    [
      "h-12 rounded-xl border-2 text-[15px] font-semibold transition active:scale-95",
      "disabled:cursor-not-allowed disabled:opacity-40 disabled:active:scale-100",
      case {location, selected?} do
        {:outside, true} -> "border-accent bg-accent-tint text-accent"
        {:inside, true} -> "border-danger bg-danger-tint text-danger"
        _ -> "border-line bg-card text-ink"
      end
    ]
  end

  defp summary?(%{auto: nil}, _routine, _expanded), do: false
  defp summary?(_preview, _routine, true), do: false
  defp summary?(%{auto: auto}, routine, false), do: routine in [nil, auto.id]

  # Opening the list shows the automatic match as chosen.
  defp checked_routine(%{auto: %{id: id}}, nil, true), do: id
  defp checked_routine(_preview, routine, _expanded), do: routine

  defp planned(%{planned_end: nil} = occurrence), do: hhmm(occurrence.planned_start)

  defp planned(occurrence),
    do: "#{hhmm(occurrence.planned_start)}–#{hhmm(occurrence.planned_end)}"

  defp hhmm(time), do: Calendar.strftime(time, "%H:%M")

  # -- events

  @impl true
  def handle_event("kind", %{"kind" => value}, socket) do
    case Map.fetch(@kinds, value) do
      {:ok, kind} ->
        location = socket.assigns.location || if(kind == :potty, do: :outside)

        {:noreply,
         socket |> assign(kind: kind, location: location) |> changed() |> refresh_preview()}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle", %{"field" => value}, socket) do
    case Map.fetch(@toggles, value) do
      {:ok, field} -> {:noreply, socket |> toggle(field) |> changed() |> refresh_preview()}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("location", %{"location" => "outside"}, socket),
    do: {:noreply, socket |> assign(location: :outside) |> changed() |> refresh_preview()}

  # „Nichts gemacht“ only exists outside.
  def handle_event("location", %{"location" => "inside"}, %{assigns: %{nothing: false}} = socket),
    do: {:noreply, socket |> assign(location: :inside) |> changed() |> refresh_preview()}

  def handle_event("location", _params, socket), do: {:noreply, socket}

  def handle_event("choose", %{"choice" => choice}, socket) do
    if Enum.any?(TimeChoice.options(), &(elem(&1, 1) == choice)),
      do: {:noreply, socket |> assign(choice: choice, time_error: nil) |> refresh_preview()},
      else: {:noreply, socket}
  end

  def handle_event("pick_name", %{"name" => name}, socket),
    do: {:noreply, socket |> assign(name: name) |> changed()}

  def handle_event("expand", _params, socket),
    do: {:noreply, assign(socket, expanded: true)}

  def handle_event("change", params, socket),
    do: {:noreply, socket |> apply_params(params) |> changed()}

  def handle_event("save", params, socket),
    do: socket |> apply_params(params) |> save()

  defp toggle(socket, :nothing) do
    if socket.assigns.nothing,
      do: assign(socket, nothing: false),
      else: assign(socket, nothing: true, pee: false, poo: false, location: :outside)
  end

  defp toggle(socket, field) do
    if Map.fetch!(socket.assigns, field),
      do: assign(socket, field, false),
      else: assign(socket, [{field, true}, nothing: false])
  end

  defp changed(socket), do: assign(socket, errors: %{})

  defp apply_params(socket, params) do
    updates =
      for {param, key} <- [
            {"name", :name},
            {"note", :note},
            {"custom", :custom},
            {"routine", :routine}
          ],
          is_binary(params[param]),
          into: %{},
          do: {key, params[param]}

    socket = assign(socket, updates)

    if Map.has_key?(updates, :custom),
      do: socket |> assign(time_error: nil) |> refresh_preview(),
      else: socket
  end

  # -- saving

  defp save(socket) do
    assigns = socket.assigns

    with {:name, false} <- {:name, missing_name?(assigns)},
         {:ok, at} <- occurred_at(assigns) do
      persist(socket, attrs(assigns, at))
    else
      {:name, true} ->
        {:noreply, assign(socket, errors: %{name: [translate_error({"is required", []})]})}

      :error ->
        {:noreply, assign(socket, time_error: @future)}
    end
  end

  defp missing_name?(%{kind: :other, name: name}), do: String.trim(name) == ""
  defp missing_name?(_assigns), do: false

  defp attrs(assigns, at) do
    base = %{
      kind: assigns.kind,
      occurred_at: at,
      note: assigns.note,
      name: if(assigns.kind == :other, do: assigns.name),
      routine: assigns.routine || "auto"
    }

    if assigns.kind == :potty,
      do: Map.merge(base, Map.take(assigns, @potty_fields)),
      else: base
  end

  defp persist(%{assigns: %{event: nil}} = socket, attrs) do
    attrs
    |> Daily.log_event(actor: socket.assigns.current_user)
    |> finish(socket, "Eingetragen.")
  end

  defp persist(%{assigns: %{event: event}} = socket, attrs) do
    event
    |> Daily.update_event(attrs, actor: socket.assigns.current_user)
    |> finish(socket, "Gespeichert.")
  end

  defp finish({:ok, _event}, socket, message) do
    {:noreply, socket |> put_flash(:info, message) |> push_patch(to: socket.assigns.return_to)}
  end

  defp finish({:error, error}, socket, _message) do
    {:noreply, socket |> assign(errors: error_map(error)) |> refresh_preview()}
  end

  defp error_map(%{errors: errors}) when is_list(errors) and errors != [] do
    errors
    |> Enum.flat_map(&form_errors/1)
    |> Enum.group_by(fn {field, _message} -> field end, fn {_field, message} -> message end)
    |> Map.new(fn {field, messages} -> {field, Enum.uniq(messages)} end)
  end

  defp error_map(_error), do: %{base: [@failed]}

  defp form_errors(error) do
    if AshPhoenix.FormData.Error.impl_for(error) do
      error
      |> AshPhoenix.FormData.Error.to_form_error()
      |> List.wrap()
      |> Enum.map(fn {field, message, vars} ->
        {placed(field), translate_error({message, vars})}
      end)
    else
      [{:base, @failed}]
    end
  end

  defp placed(field) when field in @placed_fields, do: field
  defp placed(_field), do: :base
end
