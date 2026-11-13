defmodule PuppyLogWeb.HealthFormLive do
  @moduledoc """
  Create or edit a health entry („Termin eintragen“, entwuerfe/09): kind, title,
  due date, and depending on the kind a time, place and assignee (vet visits),
  a repetition (care items) or the vaccine batch (vaccinations). New entries can
  be entered as already done to catch up on the past. Editing also offers to
  delete the entry.

  Values that only fit another kind are cleared whenever the kind changes, so
  hidden fields never block saving.
  """

  use PuppyLogWeb, :live_view

  import PuppyLogWeb.HealthRow, only: [kind_label: 1]

  alias AshPhoenix.Form
  alias PuppyLog.{Accounts, Clock, Daily, Puppy}
  alias PuppyLog.Puppy.{DueAge, HealthEntry}

  on_mount {PuppyLogWeb.LiveUserAuth, :live_user_required}

  @kind_tiles [
    {:vaccination, "syringe"},
    {:deworming, "pill"},
    {:flea_tick, "tick"},
    {:other_care, "heart"},
    {:vet_visit, "stethoscope"}
  ]
  @care_kinds Enum.map(HealthEntry.care_kinds(), &Atom.to_string/1)
  @default_repeat_weeks "4"
  # stepper fields with their bounds (as in the resource's constraints)
  @steppers %{
    "remind_days_before" => {:remind_days_before, 0, 14},
    "repeat_weeks" => {:repeat_weeks, 1, 104}
  }
  @unit_options [weeks: "Wochen", months: "Monate"]
  @gone "Diesen Eintrag gibt es nicht mehr."

  @impl true
  def mount(params, _session, socket) do
    socket =
      assign(socket,
        kind_tiles: @kind_tiles,
        members: members(socket),
        birth_date: birth_date(socket),
        unit_options: @unit_options
      )

    {:ok, init(socket, socket.assigns.live_action, params)}
  end

  defp init(socket, :new, _params) do
    days = Daily.settings(authorize?: false).health_reminder_days

    form =
      Form.for_create(HealthEntry, :create,
        actor: socket.assigns.current_user,
        domain: Puppy,
        params: %{"remind_days_before" => to_string(days)}
      )

    assign(socket,
      page_title: "Termin eintragen",
      entry: nil,
      form: to_form(form),
      repeat?: false,
      done?: false,
      due_mode: "date"
    )
  end

  defp init(socket, :edit, %{"id" => id}) do
    case Puppy.get_health_entry(id, actor: socket.assigns.current_user) do
      {:ok, entry} ->
        form = Form.for_update(entry, :update, actor: socket.assigns.current_user, domain: Puppy)

        assign(socket,
          page_title: "Eintrag bearbeiten",
          entry: entry,
          form: to_form(form),
          repeat?: entry.repeat_weeks != nil,
          done?: false,
          due_mode: if(entry.due_age, do: "age", else: "date")
        )

      {:error, _missing} ->
        socket
        |> put_flash(:error, @gone)
        |> push_navigate(to: ~p"/health")
    end
  end

  @impl true
  def render(assigns) do
    kind = field_string(assigns.form[:kind].value)

    assigns =
      assign(assigns,
        kind: kind,
        vet?: kind == "vet_visit",
        care?: kind in @care_kinds,
        today: Clock.today()
      )

    assigns = assign(assigns, age?: !assigns.vet? and assigns.due_mode == "age")

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.top_bar title={@page_title} close={~p"/health"} />

      <.form
        for={@form}
        id="health-form"
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col gap-5"
      >
        <section class="flex flex-col gap-2">
          <.section_label>Art</.section_label>
          <div class="grid grid-cols-6 gap-2" role="radiogroup" aria-label="Art">
            <label
              :for={{kind, icon} <- @kind_tiles}
              class={[
                "flex h-[76px] cursor-pointer flex-col items-center justify-center gap-1 rounded-[14px] border-2 px-1 text-center transition active:scale-95",
                "has-focus-visible:ring-4 has-focus-visible:ring-accent/25",
                if(kind in [:other_care, :vet_visit], do: "col-span-3", else: "col-span-2"),
                tile_class(@kind == Atom.to_string(kind))
              ]}
            >
              <input
                type="radio"
                name={@form[:kind].name}
                value={kind}
                checked={@kind == Atom.to_string(kind)}
                class="sr-only"
              />
              <.pl_icon name={icon} class="size-6" />
              <span class="text-[12px] leading-4 font-semibold">{kind_label(kind)}</span>
            </label>
          </div>
          <.field_errors
            :if={
              @form[:kind].errors != [] and
                (@form.source.submitted_once? or used_input?(@form[:kind]))
            }
            errors={["Bitte eine Art wählen."]}
          />
        </section>

        <.input
          field={@form[:title]}
          label="Bezeichnung"
          autocomplete="off"
          maxlength="80"
          placeholder={title_placeholder(@kind)}
        />

        <section :if={!@vet?} class="flex flex-col gap-2">
          <.section_label>Fällig</.section_label>
          <div
            class="grid grid-cols-2 gap-1 rounded-[14px] bg-field p-1"
            role="radiogroup"
            aria-label="Fällig"
          >
            <label
              :for={{mode, label} <- [{"date", "Datum"}, {"age", "Alter"}]}
              class={[
                "flex h-10 items-center justify-center rounded-[10px] text-[14px] font-semibold transition",
                "has-focus-visible:ring-4 has-focus-visible:ring-accent/25",
                if(mode == "age" and is_nil(@birth_date),
                  do: "cursor-not-allowed text-muted/50",
                  else: "cursor-pointer active:scale-95"
                ),
                segment_class(@due_mode == mode)
              ]}
            >
              <input
                type="radio"
                name="due_mode"
                value={mode}
                checked={@due_mode == mode}
                disabled={mode == "age" and is_nil(@birth_date)}
                class="sr-only"
              />
              {label}
            </label>
          </div>
          <p :if={is_nil(@birth_date)} class="px-0.5 text-[12.5px] leading-[17px] text-muted">
            <.link navigate={~p"/profile/edit"} class="font-semibold text-accent underline">
              Geburtsdatum im Profil eintragen
            </.link>
            , dann geht auch das Alter.
          </p>
        </section>

        <div :if={@age?} id="health-due-age" class="flex flex-col gap-2">
          <div class="grid grid-cols-[7rem_1fr] items-start gap-2">
            <.input
              field={@form[:due_age]}
              type="number"
              inputmode="numeric"
              label="Alter"
              min="1"
              max={DueAge.ranges() |> Map.fetch!(unit_atom(@form[:due_age_unit].value)) |> Enum.max()}
            />
            <fieldset class="flex flex-col gap-1">
              <legend class={[label_class(), "mb-1"]}>Einheit</legend>
              <div
                class="grid grid-cols-2 gap-1 rounded-[14px] bg-field p-1"
                role="radiogroup"
                aria-label="Einheit"
              >
                <label
                  :for={{unit, label} <- @unit_options}
                  class={[
                    "flex h-10 cursor-pointer items-center justify-center rounded-[10px] text-[14px] font-semibold transition active:scale-95",
                    "has-focus-visible:ring-4 has-focus-visible:ring-accent/25",
                    segment_class(unit_atom(@form[:due_age_unit].value) == unit)
                  ]}
                >
                  <input
                    type="radio"
                    name={@form[:due_age_unit].name}
                    value={unit}
                    checked={unit_atom(@form[:due_age_unit].value) == unit}
                    class="sr-only"
                  />
                  {label}
                </label>
              </div>
            </fieldset>
          </div>
          <p
            :if={preview = age_preview(@form, @birth_date)}
            id="health-due-age-preview"
            class="px-0.5 text-[13px] font-semibold text-accent-dark"
            aria-live="polite"
          >
            → {Format.short_date(preview)}
          </p>
        </div>

        <div class={["grid gap-2", @vet? && "grid-cols-2"]}>
          <.input
            :if={!@age?}
            field={@form[:due_on]}
            type="date"
            label={if @care?, do: "Fällig am", else: "Datum"}
          />
          <.input
            :if={@vet?}
            field={@form[:due_time]}
            type="time"
            label="Uhrzeit"
            value={time_value(@form[:due_time].value)}
          />
        </div>

        <.input
          :if={@vet?}
          field={@form[:location]}
          label="Ort"
          autocomplete="off"
          maxlength="120"
          placeholder="Optional, zum Beispiel Praxis Dr. Berg"
        />

        <.input
          :if={@vet?}
          field={@form[:assignee_id]}
          type="select"
          label="Zuständig"
          options={[{"Niemand", ""} | Enum.map(@members, &{Format.user_name(&1), &1.id})]}
        />

        <section class="flex flex-col gap-2">
          <.card flush>
            <div id="health-remind" class="flex min-h-16 items-center gap-3 px-4 py-2.5">
              <div class="min-w-0 flex-1">
                <p class="text-[15px] font-medium">Erinnern</p>
                <p class="text-[12.5px] text-muted" aria-live="polite">
                  {remind_label(int_value(@form[:remind_days_before].value))}
                </p>
              </div>
              <.stepper field={@form[:remind_days_before]} label="Tage vorher" />
            </div>

            <div :if={@care?} class="border-t border-divider">
              <label class="flex min-h-16 cursor-pointer items-center gap-3 px-4 py-2.5">
                <div class="min-w-0 flex-1">
                  <p class="text-[15px] font-medium">Wiederholen</p>
                  <p class="text-[12.5px] text-muted">Nach Erledigen kommt der nächste Termin</p>
                </div>
                <.switch id="health-repeat" name="repeat" checked={@repeat?} label="Wiederholen" />
              </label>
              <div
                :if={@repeat?}
                id="health-repeat-weeks"
                class="flex min-h-14 items-center gap-3 border-t border-divider px-4 py-2"
              >
                <p class="min-w-0 flex-1 text-[15px] font-medium" aria-live="polite">
                  {weeks_label(int_value(@form[:repeat_weeks].value))}
                </p>
                <.stepper field={@form[:repeat_weeks]} label="Wochen" />
              </div>
            </div>
          </.card>
          <p class="px-0.5 text-[12.5px] leading-[17px] text-muted">
            Die Erinnerung kommt über euer Kalender-Abo.
          </p>
        </section>

        <.card :if={!@entry} flush>
          <label class="flex min-h-16 cursor-pointer items-center gap-3 px-4 py-2.5">
            <div class="min-w-0 flex-1">
              <p class="text-[15px] font-medium">Bereits erledigt</p>
              <p class="text-[12.5px] text-muted">Zum Nachtragen, zum Beispiel aus dem Impfpass</p>
            </div>
            <.switch id="health-done" name="done" checked={@done?} label="Bereits erledigt" />
          </label>
          <div :if={@done?} class="border-t border-divider px-4 pt-2.5 pb-3.5">
            <.input field={@form[:done_on]} type="date" label="Erledigt am" max={@today} />
          </div>
        </.card>

        <.input
          :if={@kind == "vaccination"}
          field={@form[:batch]}
          label="Impfstoff/Charge"
          autocomplete="off"
          maxlength="120"
          placeholder="Optional, vom Aufkleber im Impfpass"
        />

        <.input
          field={@form[:notes]}
          type="textarea"
          label="Notiz"
          rows="3"
          maxlength="1000"
          placeholder="Optional"
        />

        <div class="flex flex-col gap-1">
          <.action_button type="submit" phx-disable-with="Speichert …">Speichern</.action_button>
          <.action_button
            :if={@entry}
            type="button"
            variant={:danger}
            phx-click="delete"
            data-confirm="Diesen Eintrag löschen?"
          >
            Eintrag löschen
          </.action_button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true, doc: "accessible name of the value"

  # −/+ pair that changes a hidden number input on the server (see "step").
  defp stepper(assigns) do
    {_attribute, lowest, highest} = Map.fetch!(@steppers, to_string(assigns.field.field))
    value = int_value(assigns.field.value)
    assigns = assign(assigns, value: value, min?: value <= lowest, max?: value >= highest)

    ~H"""
    <div
      class="flex h-10 shrink-0 items-stretch overflow-hidden rounded-xl border border-field bg-card"
      role="group"
      aria-label={@label}
    >
      <input type="hidden" id={@field.id} name={@field.name} value={@value} />
      <button
        :for={{delta, sign, name, disabled} <- [{-1, "−", "weniger", @min?}, {1, "+", "mehr", @max?}]}
        type="button"
        phx-click="step"
        phx-value-field={@field.field}
        phx-value-delta={delta}
        aria-label={name}
        disabled={disabled}
        class={[
          "w-11 text-[22px] leading-none text-accent transition hover:bg-accent-tint active:bg-accent-tint",
          "disabled:cursor-not-allowed disabled:text-muted/40 disabled:hover:bg-transparent",
          delta > 0 && "border-l border-divider"
        ]}
      >
        {sign}
      </button>
    </div>
    """
  end

  attr :errors, :list, required: true

  defp field_errors(assigns) do
    ~H"""
    <p
      :for={message <- @errors}
      class="px-0.5 text-[12.5px] leading-[17px] font-semibold text-danger"
    >
      {message}
    </p>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params} = all, socket) do
    socket = assign_choices(socket, all)
    form = Form.validate(socket.assigns.form, normalize(params, socket.assigns))
    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"form" => params} = all, socket) do
    socket = assign_choices(socket, all)

    case Form.submit(socket.assigns.form, params: normalize(params, socket.assigns)) do
      {:ok, _entry} ->
        {:noreply,
         socket
         |> put_flash(:info, "Gespeichert.")
         |> push_navigate(to: ~p"/health")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  def handle_event("step", %{"field" => field, "delta" => delta}, socket)
      when is_map_key(@steppers, field) and delta in ["-1", "1"] do
    {attribute, lowest, highest} = Map.fetch!(@steppers, field)
    form = socket.assigns.form
    value = int_value(form[attribute].value) + String.to_integer(delta)
    params = Map.put(form.source.params, field, to_string(value |> max(lowest) |> min(highest)))

    {:noreply, assign(socket, form: Form.validate(form, params))}
  end

  def handle_event("delete", _params, socket) do
    case Puppy.delete_health_entry(socket.assigns.entry, actor: socket.assigns.current_user) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Gelöscht.")
         |> push_navigate(to: ~p"/health")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Löschen hat nicht geklappt.")}
    end
  end

  defp assign_choices(socket, params) do
    assign(socket,
      due_mode: params["due_mode"] || socket.assigns.due_mode,
      repeat?: params["repeat"] == "true",
      done?: socket.assigns.live_action == :new and params["done"] == "true"
    )
  end

  # Clears what does not fit the chosen kind and fills in what the switches imply.
  defp normalize(params, assigns) do
    kind = params["kind"]

    params
    |> keep_only(kind == "vet_visit", ~w(due_time location assignee_id))
    |> keep_only(kind == "vaccination", ~w(batch))
    |> due(kind != "vet_visit" and assigns.due_mode == "age")
    |> repeat_weeks(kind in @care_kinds and assigns.repeat?)
    |> done(assigns)
  end

  defp keep_only(params, true, _fields), do: params
  defp keep_only(params, false, fields), do: Map.merge(params, Map.new(fields, &{&1, nil}))

  # In age mode the server computes the date from the age.
  defp due(params, true) do
    params
    |> Map.delete("due_on")
    |> Map.update("due_age_unit", "weeks", &if(&1 in [nil, ""], do: "weeks", else: &1))
  end

  defp due(params, false), do: Map.merge(params, %{"due_age" => nil, "due_age_unit" => nil})

  defp repeat_weeks(params, false), do: Map.put(params, "repeat_weeks", nil)

  defp repeat_weeks(params, true) do
    case params["repeat_weeks"] do
      weeks when weeks in [nil, ""] -> Map.put(params, "repeat_weeks", @default_repeat_weeks)
      _weeks -> params
    end
  end

  defp done(params, %{live_action: :new, done?: true}) do
    case params["done_on"] do
      date when date in [nil, ""] ->
        Map.merge(params, %{"status" => "done", "done_on" => Date.to_iso8601(Clock.today())})

      _date ->
        Map.put(params, "status", "done")
    end
  end

  defp done(params, %{live_action: :new}), do: Map.drop(params, ["status", "done_on"])
  defp done(params, _edit), do: params

  defp members(socket) do
    actor = socket.assigns.current_user
    actor |> then(&Accounts.list_users!(actor: &1)) |> Enum.sort_by(&(&1.id != actor.id))
  end

  defp segment_class(true), do: "bg-card text-accent shadow-sm"
  defp segment_class(false), do: "text-ink/70"

  defp unit_atom("months"), do: :months
  defp unit_atom(:months), do: :months
  defp unit_atom(_unit), do: :weeks

  defp birth_date(socket) do
    case Puppy.get_profile(actor: socket.assigns.current_user) do
      {:ok, %{birth_date: %Date{} = date}} -> date
      _none -> nil
    end
  end

  # The date an entered age leads to, nil while the age is missing or out of range.
  defp age_preview(_form, nil), do: nil

  defp age_preview(form, birth_date) do
    unit = unit_atom(form[:due_age_unit].value)
    age = int_value(form[:due_age].value)

    if age in Map.fetch!(DueAge.ranges(), unit), do: DueAge.due_on(birth_date, age, unit)
  end

  defp tile_class(true), do: "border-accent bg-accent-tint text-accent"
  defp tile_class(false), do: "border-line bg-card text-ink hover:border-accent/40"

  defp title_placeholder("vaccination"), do: "Zum Beispiel Tollwut"
  defp title_placeholder("deworming"), do: "Zum Beispiel Milbemax"
  defp title_placeholder("flea_tick"), do: "Zum Beispiel Zeckentablette"
  defp title_placeholder("other_care"), do: "Zum Beispiel Zahnkontrolle"
  defp title_placeholder("vet_visit"), do: "Zum Beispiel Kontrolle nach der Impfung"
  defp title_placeholder(_kind), do: nil

  defp remind_label(0), do: "Am Tag selbst"
  defp remind_label(1), do: "1 Tag vorher"
  defp remind_label(days), do: "#{days} Tage vorher"

  defp weeks_label(1), do: "Jede Woche"
  defp weeks_label(weeks), do: "Alle #{weeks} Wochen"

  defp int_value(value) when is_integer(value), do: value

  defp int_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, _rest} -> number
      :error -> 0
    end
  end

  defp int_value(nil), do: 0

  defp field_string(nil), do: nil
  defp field_string(value), do: to_string(value)

  defp time_value(%Time{} = time), do: Calendar.strftime(time, "%H:%M")
  defp time_value(value) when is_binary(value), do: String.slice(value, 0, 5)
  defp time_value(nil), do: nil
end
