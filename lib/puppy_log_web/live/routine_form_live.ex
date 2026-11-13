defmodule PuppyLogWeb.RoutineFormLive do
  @moduledoc """
  Create or edit a routine („Routine bearbeiten“, entwuerfe/07): name, the
  kind of event that ticks it off, a fixed time or a time window, weekdays,
  assignee, reminder and follow-up. Editing also offers to archive it
  („Routine löschen“), which keeps its history.

  Does not depend on the puppy's arrival date: the daily plan can be prepared
  before the puppy moves in.
  """

  use PuppyLogWeb, :live_view

  alias AshPhoenix.Form
  alias PuppyLog.{Accounts, Daily}
  alias PuppyLog.Daily.Routine

  on_mount {PuppyLogWeb.LiveUserAuth, :live_user_required}

  @kind_tiles [
    {:potty, "Lösen", "pipi"},
    {:meal, "Mahlzeit", "bowl"},
    {:walk, "Gassi", "gassi"},
    {:sleep, "Schlaf", "moon"},
    {:play, "Spiel", "ball"},
    {:training, "Training", "target"},
    {:manual, "Nur abhaken", "check"}
  ]
  @kind_icons Map.new(@kind_tiles, fn {kind, _label, icon} -> {kind, icon} end)
  @follow_up_choices [15, 30, 45, 60]
  @default_follow_up "30"

  @doc "Icon name (`PuppyLogWeb.UI.pl_icon/1`) of a routine kind."
  def kind_icon(kind), do: Map.fetch!(@kind_icons, kind)

  @impl true
  def mount(params, _session, socket) do
    socket = assign(socket, kind_tiles: @kind_tiles, members: members(socket))
    {:ok, init(socket, socket.assigns.live_action, params)}
  end

  defp init(socket, :new, _params) do
    form =
      Form.for_create(Routine, :create,
        actor: socket.assigns.current_user,
        domain: Daily,
        params: %{"weekdays" => Enum.map(1..7, &to_string/1), "remind?" => "true"}
      )

    assign(socket,
      page_title: "Neue Routine",
      routine: nil,
      form: to_form(form),
      mode: "fixed",
      follow_up?: false
    )
  end

  defp init(socket, :edit, %{"id" => id}) do
    case Daily.get_routine(id, actor: socket.assigns.current_user) do
      {:ok, %{archived_at: nil} = routine} ->
        form =
          Form.for_update(routine, :update, actor: socket.assigns.current_user, domain: Daily)

        assign(socket,
          page_title: "Routine bearbeiten",
          routine: routine,
          form: to_form(form),
          mode: if(routine.ends_at, do: "window", else: "fixed"),
          follow_up?: routine.follow_up_minutes != nil
        )

      _missing_or_archived ->
        socket
        |> put_flash(:error, "Diese Routine gibt es nicht mehr.")
        |> push_navigate(to: ~p"/routines")
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        kind: field_string(assigns.form[:kind].value),
        weekdays: weekday_numbers(assigns.form[:weekdays].value),
        follow_up_options: Enum.map(@follow_up_choices, &{"#{&1} Minuten", &1})
      )

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.top_bar title={@page_title} close={~p"/routines"} />

      <.form
        for={@form}
        id="routine-form"
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col gap-5"
      >
        <.input
          field={@form[:name]}
          label="Name"
          autocomplete="off"
          maxlength="60"
          placeholder="Zum Beispiel Pipi-Runde nach dem Aufwachen"
        />

        <section class="flex flex-col gap-2">
          <.section_label>Wird erledigt durch</.section_label>
          <div class="grid grid-cols-4 gap-2" role="radiogroup" aria-label="Wird erledigt durch">
            <label
              :for={{kind, label, icon} <- @kind_tiles}
              class={[
                "flex h-[76px] cursor-pointer flex-col items-center justify-center gap-1 rounded-[14px] border-2 transition active:scale-95",
                "has-focus-visible:ring-4 has-focus-visible:ring-accent/25",
                tile_class(kind, @kind == Atom.to_string(kind))
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
              <span class="text-[12px] leading-4 font-semibold">{label}</span>
            </label>
          </div>
          <.field_errors :if={used_input?(@form[:kind])} errors={@form[:kind].errors} />
          <p class="px-0.5 text-[12.5px] leading-[17px] text-muted">
            {kind_hint(@kind)}
          </p>
        </section>

        <section class="flex flex-col gap-2">
          <.section_label>Wann</.section_label>
          <div
            class="grid grid-cols-2 gap-1 rounded-xl bg-mist p-1"
            role="radiogroup"
            aria-label="Wann"
          >
            <label
              :for={{value, label} <- [{"fixed", "Feste Uhrzeit"}, {"window", "Zeitfenster"}]}
              class={[
                "flex h-10 cursor-pointer items-center justify-center rounded-[9px] text-[14px] font-semibold transition",
                "has-focus-visible:ring-2 has-focus-visible:ring-accent/40",
                if(@mode == value,
                  do: "bg-card text-accent shadow-[0_1px_2px_rgba(20,32,27,0.15)]",
                  else: "text-muted hover:text-ink"
                )
              ]}
            >
              <input
                type="radio"
                name="mode"
                value={value}
                checked={@mode == value}
                class="sr-only"
              />
              {label}
            </label>
          </div>
          <div class={["grid gap-2", @mode == "window" && "grid-cols-2"]}>
            <.input
              field={@form[:starts_at]}
              type="time"
              label={if @mode == "window", do: "Von", else: "Uhrzeit"}
              value={time_value(@form[:starts_at].value)}
            />
            <.input
              :if={@mode == "window"}
              field={@form[:ends_at]}
              type="time"
              label="Bis"
              value={time_value(@form[:ends_at].value)}
            />
          </div>
        </section>

        <section class="flex flex-col gap-2">
          <.section_label>An diesen Tagen</.section_label>
          <div class="grid grid-cols-7 gap-1.5" role="group" aria-label="An diesen Tagen">
            <label
              :for={{name, day} <- Enum.with_index(Format.weekday_names(), 1)}
              class={[
                "flex h-11 cursor-pointer items-center justify-center rounded-full border-2 text-[13px] font-semibold transition active:scale-95",
                "has-focus-visible:ring-4 has-focus-visible:ring-accent/25",
                if(day in @weekdays,
                  do: "border-accent bg-accent text-white",
                  else: "border-line bg-card text-ink hover:border-accent/40"
                )
              ]}
            >
              <input
                type="checkbox"
                name={@form[:weekdays].name <> "[]"}
                value={day}
                checked={day in @weekdays}
                class="sr-only"
              />
              {name}
            </label>
          </div>
          <.field_errors
            :if={@form[:weekdays].errors != []}
            errors={["Bitte mindestens einen Tag wählen."]}
          />
        </section>

        <.input
          field={@form[:assignee_id]}
          type="select"
          label="Zuständig"
          options={[{"Niemand", ""} | Enum.map(@members, &{Format.user_name(&1), &1.id})]}
        />

        <.card flush>
          <label class="flex min-h-16 cursor-pointer items-center gap-3 px-4 py-2.5">
            <div class="min-w-0 flex-1">
              <p class="text-[15px] font-medium">Erinnern</p>
              <p class="text-[12.5px] text-muted">
                {if @mode == "window",
                  do: "Zu Beginn des Zeitfensters",
                  else: "Zur festen Uhrzeit"}
              </p>
            </div>
            <.switch
              id="routine-remind"
              name={@form[:remind?].name}
              checked={checked?(@form[:remind?].value)}
              label="Erinnern"
            />
          </label>
          <div class="border-t border-divider">
            <label class="flex min-h-16 cursor-pointer items-center gap-3 px-4 py-2.5">
              <div class="min-w-0 flex-1">
                <p class="text-[15px] font-medium">Nachfragen, wenn offen</p>
                <p class="text-[12.5px] text-muted">
                  {if @follow_up?,
                    do: "Nach #{@form[:follow_up_minutes].value} Minuten",
                    else: "Aus"}
                </p>
              </div>
              <.switch
                id="routine-follow-up"
                name="follow_up"
                checked={@follow_up?}
                label="Nachfragen, wenn offen"
              />
            </label>
            <div :if={@follow_up?} class="px-4 pb-3">
              <.input
                field={@form[:follow_up_minutes]}
                type="select"
                label="Nachfragen nach"
                options={@follow_up_options}
              />
            </div>
          </div>
        </.card>

        <div class="flex flex-col gap-1">
          <.action_button type="submit" phx-disable-with="Speichert …">Speichern</.action_button>
          <.action_button
            :if={@routine}
            type="button"
            variant={:danger}
            phx-click="archive"
            data-confirm="Diese Routine löschen? Der Verlauf bleibt erhalten."
          >
            Routine löschen
          </.action_button>
        </div>
      </.form>
    </Layouts.app>
    """
  end

  attr :errors, :list, required: true

  defp field_errors(assigns) do
    ~H"""
    <p
      :for={message <- @errors}
      class="px-0.5 text-[12.5px] leading-[17px] font-semibold text-danger"
    >
      {translate(message)}
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
      {:ok, _routine} ->
        {:noreply,
         socket
         |> put_flash(:info, "Routine gespeichert.")
         |> push_navigate(to: ~p"/routines")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
  end

  def handle_event("archive", _params, socket) do
    case Daily.archive_routine(socket.assigns.routine, actor: socket.assigns.current_user) do
      {:ok, _routine} ->
        {:noreply,
         socket
         |> put_flash(:info, "Routine gelöscht. Der Verlauf bleibt erhalten.")
         |> push_navigate(to: ~p"/routines")}

      {:error, _error} ->
        {:noreply, put_flash(socket, :error, "Löschen hat nicht geklappt.")}
    end
  end

  defp assign_choices(socket, params) do
    assign(socket,
      mode: if(params["mode"] == "window", do: "window", else: "fixed"),
      follow_up?: params["follow_up"] == "true"
    )
  end

  # Fills in what the switches and the segment imply: unchecked weekday chips
  # send nothing, a fixed time has no end, follow-up off means no minutes.
  defp normalize(params, %{mode: mode, follow_up?: follow_up?}) do
    params
    |> Map.put_new("weekdays", [])
    |> then(&if mode == "fixed", do: Map.put(&1, "ends_at", nil), else: &1)
    |> follow_up_minutes(follow_up?)
  end

  defp follow_up_minutes(params, false), do: Map.put(params, "follow_up_minutes", nil)

  defp follow_up_minutes(params, true) do
    case params["follow_up_minutes"] do
      minutes when minutes in [nil, ""] ->
        Map.put(params, "follow_up_minutes", @default_follow_up)

      _minutes ->
        params
    end
  end

  defp members(socket) do
    actor = socket.assigns.current_user
    actor |> then(&Accounts.list_users!(actor: &1)) |> Enum.sort_by(&(&1.id != actor.id))
  end

  defp tile_class(:potty, true), do: "border-pipi bg-pipi-tint text-pipi"
  defp tile_class(_kind, true), do: "border-accent bg-accent-tint text-accent"
  defp tile_class(_kind, false), do: "border-line bg-card text-ink hover:border-accent/40"

  defp kind_hint("manual"), do: "Wird nur von Hand auf „Heute“ abgehakt."

  defp kind_hint(_kind),
    do: "Trägt jemand ein passendes Ereignis ein, wird die Routine automatisch abgehakt."

  defp translate(message) when is_binary(message), do: message
  defp translate(error), do: PuppyLogWeb.CoreComponents.translate_error(error)

  defp field_string(nil), do: nil
  defp field_string(value), do: to_string(value)

  defp weekday_numbers(value) do
    value
    |> List.wrap()
    |> Enum.flat_map(fn
      day when is_integer(day) ->
        [day]

      day when is_binary(day) ->
        case Integer.parse(day) do
          {day, ""} -> [day]
          _other -> []
        end
    end)
  end

  defp checked?(value), do: value in [true, "true"]

  defp time_value(%Time{} = time), do: Calendar.strftime(time, "%H:%M")
  defp time_value(value) when is_binary(value), do: String.slice(value, 0, 5)
  defp time_value(nil), do: nil
end
