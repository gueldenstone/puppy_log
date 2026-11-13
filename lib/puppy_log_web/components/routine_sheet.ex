defmodule PuppyLogWeb.RoutineSheet do
  @moduledoc """
  Bottom sheet for one planned routine: tick off with the real time (quick
  time choice), record a Lösen outcome (Pipi, Kaka, beides, nichts, always
  outside), skip, or reopen a done or skipped routine.

  After an action it patches to `return_to` with a flash. Pass `default_at` to
  start the time choice on „Uhrzeit“ with that value (e.g. the planned time of
  a past day).
  """

  use PuppyLogWeb, :live_component

  alias PuppyLog.{Clock, Daily}
  alias PuppyLogWeb.TimeChoice

  @outcomes [
    {"pee", "Pipi", %{pee: true}},
    {"poo", "Kaka", %{poo: true}},
    {"both", "Beides", %{pee: true, poo: true}},
    {"nothing", "Nichts", %{nothing: true}}
  ]

  @impl true
  def update(assigns, socket) do
    first? =
      socket.assigns[:occurrence] == nil or socket.assigns.occurrence.id != assigns.occurrence.id

    socket = assign(socket, assigns)
    {:ok, if(first?, do: reset_time(socket), else: socket)}
  end

  defp reset_time(socket) do
    case socket.assigns[:default_at] do
      %DateTime{} = at ->
        assign(socket, choice: "custom", custom: TimeChoice.to_input(at), time_error: nil)

      nil ->
        assign(socket, choice: "now", custom: TimeChoice.to_input(Clock.now()), time_error: nil)
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, outcomes: @outcomes, options: TimeChoice.options())

    ~H"""
    <div>
      <.sheet id={@id} title={@occurrence.name} close={@return_to}>
        <p class="-mt-2 text-[14px] text-muted">{planned(@occurrence)}</p>

        <%= if @occurrence.status == :open do %>
          <div class="flex flex-col gap-2">
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
            <form
              :if={@choice == "custom"}
              id={"#{@id}-time"}
              phx-change="custom"
              phx-submit="custom"
              phx-target={@myself}
            >
              <.input
                type="datetime-local"
                name="custom"
                id={"#{@id}-custom"}
                label="Uhrzeit"
                value={@custom}
                max={TimeChoice.to_input(Clock.now())}
                errors={List.wrap(@time_error)}
              />
            </form>
            <p
              :if={@time_error && @choice != "custom"}
              class="text-[12.5px] font-semibold text-danger"
            >
              {@time_error}
            </p>
          </div>

          <div :if={@occurrence.kind == :potty} class="flex flex-col gap-2">
            <.section_label>Was war draußen?</.section_label>
            <div class="grid grid-cols-4 gap-2">
              <button
                :for={{value, label, _attrs} <- @outcomes}
                type="button"
                phx-click="potty"
                phx-value-outcome={value}
                phx-target={@myself}
                phx-disable-with={label}
                class={[
                  "flex h-[76px] flex-col items-center justify-center gap-1 rounded-[14px] border-2 border-line bg-card text-[13px] font-semibold",
                  "transition hover:border-accent/40 active:scale-95 phx-click-loading:opacity-60",
                  outcome_color(value)
                ]}
              >
                <span class={["grid size-9 place-items-center rounded-full", outcome_tint(value)]}>
                  <.outcome_icon value={value} />
                </span>
                {label}
              </button>
            </div>
            <p class="px-0.5 text-[12.5px] text-muted">Zählt für die Stubenreinheit.</p>
          </div>

          <.action_button
            :if={@occurrence.kind != :potty}
            type="button"
            phx-click="complete"
            phx-target={@myself}
            phx-disable-with="Abhaken …"
          >
            <.pl_icon name="check" class="size-5" /> Abhaken
          </.action_button>
          <.action_button
            variant={:secondary}
            type="button"
            phx-click="skip"
            phx-target={@myself}
            class="!border-line !text-warn hover:!bg-warn-tint"
          >
            <.pl_icon name="skip" class="size-5" /> Überspringen
          </.action_button>
        <% else %>
          <.card class="flex items-center gap-3">
            <span class={[
              "grid size-10 shrink-0 place-items-center rounded-full",
              if(@occurrence.status == :done,
                do: "bg-accent-tint text-accent",
                else: "bg-mist text-muted"
              )
            ]}>
              <.pl_icon
                name={if @occurrence.status == :done, do: "check", else: "skip"}
                class="size-5"
              />
            </span>
            <div class="min-w-0">
              <p class="font-semibold">{outcome(@occurrence, @current_user)}</p>
              <p :if={@occurrence.event_id} class="text-[12.5px] text-muted">
                Mit einem Eintrag erledigt. Der Eintrag bleibt beim Wieder-Öffnen erhalten.
              </p>
            </div>
          </.card>
          <.action_button type="button" phx-click="reopen" phx-target={@myself}>
            <.pl_icon name="undo" class="size-5" /> Wieder öffnen
          </.action_button>
        <% end %>
      </.sheet>
    </div>
    """
  end

  attr :value, :string, required: true

  defp outcome_icon(%{value: "pee"} = assigns), do: ~H|<.pl_icon name="pipi" class="size-5" />|
  defp outcome_icon(%{value: "poo"} = assigns), do: ~H|<.pl_icon name="kaka" class="size-5" />|

  defp outcome_icon(%{value: "both"} = assigns) do
    ~H"""
    <span class="flex -space-x-1">
      <.pl_icon name="pipi" class="size-4 text-pipi" /><.pl_icon name="kaka" class="size-4 text-kaka" />
    </span>
    """
  end

  defp outcome_icon(assigns), do: ~H|<.pl_icon name="x" class="size-5" />|

  defp outcome_color("pee"), do: "text-pipi"
  defp outcome_color("poo"), do: "text-kaka"
  defp outcome_color(_value), do: "text-ink"

  defp outcome_tint("pee"), do: "bg-pipi-tint"
  defp outcome_tint("poo"), do: "bg-kaka-tint"
  defp outcome_tint(_value), do: "bg-mist"

  @impl true
  def handle_event("choose", %{"choice" => choice}, socket) do
    {:noreply, assign(socket, choice: choice, time_error: nil)}
  end

  def handle_event("custom", %{"custom" => custom}, socket) do
    {:noreply, assign(socket, custom: custom, time_error: nil)}
  end

  def handle_event("complete", _params, socket) do
    with_time(socket, fn at ->
      socket.assigns.occurrence
      |> Daily.complete_occurrence(%{done_at: at}, actor: socket.assigns.current_user)
      |> finish(socket, "#{socket.assigns.occurrence.name} abgehakt.")
    end)
  end

  def handle_event("potty", %{"outcome" => value}, socket) do
    {_value, _label, outcome} = List.keyfind(@outcomes, value, 0, hd(@outcomes))
    occurrence = socket.assigns.occurrence

    with_time(socket, fn at ->
      %{kind: :potty, location: :outside, occurred_at: at, routine: occurrence.id}
      |> Map.merge(outcome)
      |> Daily.log_event(actor: socket.assigns.current_user)
      |> finish(socket, "#{occurrence.name} abgehakt.")
    end)
  end

  def handle_event("skip", _params, socket) do
    socket.assigns.occurrence
    |> Daily.skip_occurrence(actor: socket.assigns.current_user)
    |> finish(socket, "#{socket.assigns.occurrence.name} übersprungen.")
  end

  def handle_event("reopen", _params, socket) do
    socket.assigns.occurrence
    |> Daily.reopen_occurrence(actor: socket.assigns.current_user)
    |> finish(socket, "#{socket.assigns.occurrence.name} ist wieder offen.")
  end

  defp with_time(socket, fun) do
    case TimeChoice.resolve(socket.assigns.choice, socket.assigns.custom, Clock.now()) do
      {:ok, at} ->
        fun.(DateTime.shift_zone!(at, "Etc/UTC"))

      :error ->
        {:noreply,
         assign(socket, time_error: "Bitte eine Uhrzeit wählen, die nicht in der Zukunft liegt.")}
    end
  end

  defp finish({:ok, _result}, socket, message), do: close(socket, :info, message)

  defp finish({:error, error}, socket, _message),
    do: close(socket, :error, error_message(error))

  defp close(socket, kind, message) do
    {:noreply, socket |> put_flash(kind, message) |> push_patch(to: socket.assigns.return_to)}
  end

  @doc "German message for a failed tick-off, skip or reopen."
  @spec error_message(term) :: String.t()
  def error_message(error) do
    if already_done?(error),
      do: "Schon erledigt",
      else: "Das hat leider nicht geklappt. Bitte noch einmal versuchen."
  end

  defp already_done?(%{message: "Schon erledigt"}), do: true
  # an explicit routine choice that is no longer open (see LinkRoutine)
  defp already_done?(%{field: :routine}), do: true

  defp already_done?(%{errors: errors}) when is_list(errors),
    do: Enum.any?(errors, &already_done?/1)

  defp already_done?(_error), do: false

  defp planned(%{planned_end: nil} = occurrence),
    do: "Geplant um #{hhmm(occurrence.planned_start)}"

  defp planned(occurrence),
    do: "Geplant von #{hhmm(occurrence.planned_start)} bis #{hhmm(occurrence.planned_end)}"

  defp outcome(%{status: :done} = occurrence, current_user) do
    "Erledigt um #{occurrence.done_at |> Clock.local() |> hhmm()}" <> by(occurrence, current_user)
  end

  defp outcome(occurrence, current_user), do: "Übersprungen" <> by(occurrence, current_user)

  defp by(%{completed_by: %{} = user}, current_user), do: " · " <> Format.who(user, current_user)
  defp by(_occurrence, _current_user), do: ""

  defp hhmm(time), do: Calendar.strftime(time, "%H:%M")
end
