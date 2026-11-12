defmodule PuppyLogWeb.SettingsLive do
  @moduledoc """
  Household and notifications screen („Haushalt & Mitteilungen“, entwuerfe/08): members, push setup of this
  device, test notifications. Quiet hours and reminder settings follow with
  the routines.
  """

  use PuppyLogWeb, :live_view

  alias PuppyLog.{Accounts, Notifications}

  on_mount {PuppyLogWeb.LiveUserAuth, :live_user_required}

  @delay_seconds 15

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      PuppyLogWeb.Endpoint.subscribe("push_subscriptions:changed")
    end

    {:ok,
     socket
     |> assign(
       page_title: "Haushalt & Mitteilungen",
       vapid_public_key: vapid_public_key(),
       device: nil,
       sending: nil,
       last_result: nil,
       delay_seconds: @delay_seconds
     )
     |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.top_bar title="Haushalt & Mitteilungen" back={~p"/"} />

      <.section_label class="pt-1">Haushalt</.section_label>
      <.card flush>
        <ul class="divide-y divide-divider" id="members">
          <li
            :for={member <- @members}
            id={"member-#{member.id}"}
            class="flex min-h-14 items-center gap-3 px-4 py-2"
          >
            <.avatar user={member} current_user={@current_user} class="border-0" />
            <div class="min-w-0 flex-1">
              <p class="font-medium">{Format.user_name(member)}</p>
              <p class="text-[12.5px] text-muted">{devices_text(@subscriptions, member)}</p>
            </div>
          </li>
        </ul>
      </.card>

      <.section_label class="pt-1">Dieses Gerät</.section_label>
      <section
        id="push-setup"
        phx-hook="PushSetup"
        data-vapid-public-key={@vapid_public_key}
        class="rounded-2xl border border-line bg-card p-4"
      >
        <div class="flex items-center justify-between gap-3">
          <p class="font-semibold">Mitteilungen</p>
          <.status_chip device={@device} />
        </div>
        <.device_body device={@device} />

        <details :if={@device} class="group mt-3 text-[13px]">
          <summary class="flex min-h-11 cursor-pointer list-none items-center gap-1 text-muted">
            <.pl_icon name="right" class="size-4 transition group-open:rotate-90" />
            Technische Details
          </summary>
          <dl class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 rounded-xl bg-canvas p-3 font-mono text-[12px]">
            <dt class="text-muted">App-Modus</dt>
            <dd>{if @device["standalone"], do: "Home-Bildschirm", else: "Browser"}</dd>
            <dt class="text-muted">Berechtigung</dt>
            <dd>{@device["permission"]}</dd>
            <dt class="text-muted">Push-Dienst</dt>
            <dd class="break-all">{endpoint_host(@device["endpoint"]) || "–"}</dd>
            <dt class="text-muted">Browser</dt>
            <dd class="break-all">{@device["user_agent"]}</dd>
          </dl>
        </details>
      </section>

      <.section_label class="pt-1">Test-Benachrichtigung</.section_label>
      <.card>
        <p class="text-[14px] text-muted">
          Für einen echten Test: verzögert senden, App schließen, Handy sperren.
        </p>
        <div class="mt-3 grid grid-cols-2 gap-2">
          <.send_button target="me" delay={0} sending={@sending} disabled={@subscriptions == []}>
            An mich
          </.send_button>
          <.send_button target="all" delay={0} sending={@sending} disabled={@subscriptions == []}>
            An alle
          </.send_button>
          <.send_button
            target="me"
            delay={@delay_seconds}
            sending={@sending}
            disabled={@subscriptions == []}
          >
            An mich in {@delay_seconds} s
          </.send_button>
          <.send_button
            target="all"
            delay={@delay_seconds}
            sending={@sending}
            disabled={@subscriptions == []}
          >
            An alle in {@delay_seconds} s
          </.send_button>
        </div>

        <div :if={@last_result} id="last-result" class="mt-3 rounded-xl bg-canvas p-3 text-[14px]">
          <p class="font-medium">
            {@last_result.sent} von {length(@last_result.results)} an den Push-Dienst übergeben
          </p>
          <ul class="mt-1 space-y-1">
            <li :for={result <- @last_result.results} class="flex items-start gap-2">
              <.pl_icon
                name={if result.result == :ok, do: "check", else: "x"}
                class={[
                  "mt-0.5 size-4 shrink-0",
                  if(result.result == :ok, do: "text-accent", else: "text-danger")
                ]}
              />
              <span>
                <span class="font-medium">{result.user}</span>
                <span class="text-muted">· {describe_result(result.result)}</span>
              </span>
            </li>
          </ul>
        </div>
      </.card>

      <.card flush>
        <.link
          href={~p"/sign-out"}
          class="flex min-h-14 items-center gap-3 px-4 font-medium text-danger active:bg-danger-tint"
        >
          <.pl_icon name="logout" class="size-5" /> Auf diesem Gerät abmelden
        </.link>
      </.card>
    </Layouts.app>
    """
  end

  attr :device, :map

  defp status_chip(%{device: nil} = assigns), do: ~H"<.chip>prüfe …</.chip>"

  defp status_chip(%{device: %{"subscribed" => true}} = assigns),
    do:
      ~H|<.chip kind={:ok}><.pl_icon name="check" class="size-3" stroke_width="3" /> aktiv</.chip>|

  defp status_chip(assigns), do: ~H"<.chip kind={:warn}>nicht aktiv</.chip>"

  attr :device, :map

  defp device_body(%{device: nil} = assigns) do
    ~H"""
    <div class="mt-3 h-12 animate-pulse rounded-xl bg-canvas" />
    """
  end

  defp device_body(%{device: %{"ios" => true, "standalone" => false}} = assigns) do
    ~H"""
    <div class="mt-3 flex flex-col gap-2 text-[14px]">
      <p class="text-muted">
        Auf dem iPhone gibt es Mitteilungen nur, wenn Puppy Log auf dem Home-Bildschirm liegt:
      </p>
      <ol class="flex flex-col gap-2">
        <li
          :for={
            {step, i} <-
              Enum.with_index(
                [
                  "In Safari auf „Teilen“ tippen",
                  "„Zum Home-Bildschirm“ wählen",
                  "Puppy Log dort öffnen und anmelden"
                ],
                1
              )
          }
          class="flex items-center gap-3"
        >
          <span class="grid size-7 shrink-0 place-items-center rounded-full bg-accent-tint text-[12px] font-bold text-accent">{i}</span>
          {step}
        </li>
      </ol>
    </div>
    """
  end

  defp device_body(%{device: %{"push" => false}} = assigns) do
    ~H"""
    <p class="mt-3 text-[14px] text-muted">Dieser Browser unterstützt keine Mitteilungen.</p>
    """
  end

  defp device_body(%{device: %{"permission" => "denied"}} = assigns) do
    ~H"""
    <p class="mt-3 text-[14px] text-muted">
      Mitteilungen sind blockiert. iPhone: Einstellungen → Mitteilungen → Puppy Log → Mitteilungen erlauben.
    </p>
    """
  end

  defp device_body(%{device: %{"subscribed" => true}} = assigns) do
    ~H"""
    <div class="mt-2 flex flex-col gap-1">
      <p class="text-[14px] text-muted">Dieses Gerät bekommt Erinnerungen.</p>
      <p :if={@device["error"]} class="text-[13px] font-semibold text-danger">{@device["error"]}</p>
      <button
        type="button"
        data-push-action="unsubscribe"
        class="-ml-1 flex min-h-11 items-center self-start px-1 text-[14px] font-medium text-muted underline-offset-4 hover:text-danger hover:underline"
      >
        Auf diesem Gerät deaktivieren
      </button>
    </div>
    """
  end

  defp device_body(assigns) do
    ~H"""
    <div class="mt-2 flex flex-col gap-3">
      <p class="text-[14px] text-muted">
        Erlaube Mitteilungen, damit dieses Gerät Erinnerungen bekommt.
      </p>
      <p :if={@device["error"]} class="text-[13px] font-semibold text-danger">{@device["error"]}</p>
      <.action_button type="button" data-push-action="subscribe">
        <.pl_icon name="bell" class="size-5" /> Mitteilungen erlauben
      </.action_button>
    </div>
    """
  end

  attr :target, :string, required: true
  attr :delay, :integer, required: true
  attr :sending, :any
  attr :disabled, :boolean, default: false
  slot :inner_block, required: true

  defp send_button(assigns) do
    assigns = assign(assigns, :busy, assigns.sending == {assigns.target, assigns.delay})

    ~H"""
    <button
      type="button"
      phx-click="send_test"
      phx-value-target={@target}
      phx-value-delay={@delay}
      disabled={@disabled || @sending != nil}
      class={[
        "flex min-h-12 items-center justify-center gap-1.5 rounded-xl px-3 text-[14px] font-semibold transition active:scale-[0.97] disabled:cursor-not-allowed disabled:opacity-50",
        if(@delay == 0,
          do: "bg-accent text-white",
          else: "border-2 border-accent bg-card text-accent"
        )
      ]}
    >
      <.icon :if={@busy} name="hero-arrow-path" class="size-4 animate-spin" />
      <.pl_icon :if={!@busy} name={if @delay > 0, do: "clock", else: "send"} class="size-4" />
      {render_slot(@inner_block)}
    </button>
    """
  end

  @impl true
  def handle_event("device_status", status, socket) do
    {:noreply, assign(socket, device: status)}
  end

  def handle_event("subscribed", %{"subscription" => subscription} = params, socket) do
    attrs = %{
      endpoint: subscription["endpoint"],
      p256dh: get_in(subscription, ["keys", "p256dh"]),
      auth: get_in(subscription, ["keys", "auth"]),
      user_agent: params["user_agent"]
    }

    case Notifications.subscribe_push(attrs, actor: socket.assigns.current_user) do
      {:ok, _subscription} -> {:reply, %{ok: true}, socket}
      {:error, error} -> {:reply, %{ok: false, error: Exception.message(error)}, socket}
    end
  end

  def handle_event("unsubscribed", %{"endpoint" => endpoint}, socket) do
    # The subscription may already be gone (e.g. expired), that's fine.
    _ = Notifications.unsubscribe_push(endpoint, actor: socket.assigns.current_user)
    {:reply, %{ok: true}, socket}
  end

  def handle_event("send_test", %{"target" => target, "delay" => delay}, socket) do
    target = if target == "all", do: :all, else: :me
    delay = if delay == "0", do: 0, else: @delay_seconds
    actor = socket.assigns.current_user

    if delay == 0 do
      {:noreply,
       socket
       |> assign(sending: {to_string(target), 0})
       |> start_async(:send_test, fn -> send_test(target, actor) end)}
    else
      live_view = self()

      Task.Supervisor.start_child(PuppyLog.TaskSupervisor, fn ->
        Process.sleep(delay * 1000)
        send(live_view, {:delayed_result, send_test(target, actor)})
      end)

      {:noreply,
       put_flash(
         socket,
         :info,
         "Wird in #{delay} Sekunden gesendet. Jetzt App schließen und Handy sperren."
       )}
    end
  end

  @impl true
  def handle_async(:send_test, {:ok, result}, socket) do
    {:noreply, socket |> assign(sending: nil) |> show_result(result)}
  end

  def handle_async(:send_test, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(sending: nil)
     |> put_flash(:error, "Senden fehlgeschlagen: #{inspect(reason)}")}
  end

  @impl true
  def handle_info({:delayed_result, result}, socket), do: {:noreply, show_result(socket, result)}

  def handle_info(%Phoenix.Socket.Broadcast{topic: "push_subscriptions:changed"}, socket) do
    {:noreply, load(socket)}
  end

  defp send_test(target, actor), do: Notifications.send_test_push(target, actor: actor)

  defp show_result(socket, {:ok, result}), do: assign(socket, last_result: result)

  defp show_result(socket, {:error, error}) do
    put_flash(socket, :error, "Senden fehlgeschlagen: #{Exception.message(error)}")
  end

  defp load(socket) do
    actor = socket.assigns.current_user

    assign(socket,
      members:
        actor |> then(&Accounts.list_users!(actor: &1)) |> Enum.sort_by(&(&1.id != actor.id)),
      subscriptions: Notifications.list_push_subscriptions!(actor: actor)
    )
  end

  defp devices_text(subscriptions, member) do
    case Enum.count(subscriptions, &(&1.user_id == member.id)) do
      0 -> "Keine Mitteilungen aktiviert"
      1 -> "1 Gerät · Mitteilungen aktiv"
      n -> "#{n} Geräte · Mitteilungen aktiv"
    end
  end

  defp vapid_public_key do
    :web_push_ex |> Application.fetch_env!(:vapid) |> Keyword.fetch!(:public_key)
  end

  defp endpoint_host(nil), do: nil
  defp endpoint_host(endpoint), do: URI.parse(endpoint).host

  defp describe_result(:ok), do: "übergeben"
  defp describe_result({:error, :expired}), do: "Abo abgelaufen, Gerät entfernt"

  defp describe_result({:error, {:http_error, status, body}}),
    do: "Fehler HTTP #{status} #{inspect(body)}"

  defp describe_result({:error, %{__exception__: true} = error}), do: Exception.message(error)
  defp describe_result({:error, other}), do: inspect(other)
end
