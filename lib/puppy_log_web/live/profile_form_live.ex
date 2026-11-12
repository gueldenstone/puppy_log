defmodule PuppyLogWeb.ProfileFormLive do
  @moduledoc "Create or edit the puppy profile, including the photo (entwuerfe/03)."

  use PuppyLogWeb, :live_view

  alias AshPhoenix.Form
  alias PuppyLog.{Puppy, Uploads}

  on_mount {PuppyLogWeb.LiveUserAuth, :live_user_required}

  @max_photo_size 15_000_000

  @impl true
  def mount(_params, _session, socket) do
    actor = socket.assigns.current_user
    profile = Puppy.get_profile!(actor: actor)

    form =
      case profile do
        nil -> Form.for_create(Puppy.Profile, :create, actor: actor, domain: Puppy)
        profile -> Form.for_update(profile, :update, actor: actor, domain: Puppy)
      end

    {:ok,
     socket
     |> assign(
       page_title: if(profile, do: "Profil bearbeiten", else: "Welpenprofil anlegen"),
       profile: profile,
       form: to_form(form)
     )
     |> allow_upload(:photo,
       accept: Uploads.allowed_extensions(),
       max_entries: 1,
       max_file_size: @max_photo_size
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.form
        for={@form}
        id="profile-form"
        phx-change="validate"
        phx-submit="save"
        class="flex flex-col gap-4"
      >
        <.top_bar title={@page_title} close={if @profile, do: ~p"/profil", else: ~p"/"} />

        <section class="flex flex-col items-center gap-2" phx-drop-target={@uploads.photo.ref}>
          <label for={@uploads.photo.ref} class="relative cursor-pointer">
            <%= case @uploads.photo.entries do %>
              <% [entry | _] -> %>
                <.live_img_preview
                  entry={entry}
                  class="size-28 rounded-full object-cover"
                  alt="Vorschau des neuen Fotos"
                />
              <% [] -> %>
                <.puppy_photo profile={@profile} size="size-28" icon_class="size-12" />
            <% end %>
            <span class="absolute right-0 bottom-0 grid size-10 place-items-center rounded-full border-[3px] border-canvas bg-accent text-white">
              <.pl_icon name="camera" class="size-[18px]" />
            </span>
          </label>
          <label
            for={@uploads.photo.ref}
            class="flex min-h-11 cursor-pointer items-center text-[14px] font-semibold text-accent"
          >
            {if @profile && @profile.photo_path, do: "Foto ändern", else: "Foto auswählen"}
          </label>
          <.live_file_input upload={@uploads.photo} class="sr-only" />
          <p
            :for={err <- upload_errors(@uploads.photo) ++ entry_errors(@uploads.photo)}
            class="text-[12.5px] font-semibold text-danger"
          >
            {upload_error(err)}
          </p>
        </section>

        <.input field={@form[:name]} label="Name" autocomplete="off" />
        <.input
          field={@form[:birth_date]}
          type="date"
          label="Geburtsdatum"
          max={PuppyLog.Clock.today()}
        />
        <div class="flex flex-col gap-1.5">
          <.input field={@form[:arrival_date]} type="date" label="Einzug" />
          <p class="px-0.5 text-[12.5px] text-muted">
            Ab diesem Tag zählen Routinen und Erinnerungen.
          </p>
        </div>
        <.input field={@form[:breed]} label="Rasse" autocomplete="off" />
        <div class="flex flex-col gap-1.5">
          <.input
            field={@form[:chip_number]}
            label="Chipnummer"
            inputmode="numeric"
            autocomplete="off"
            placeholder="15 Ziffern"
          />
          <p class="px-0.5 text-[12.5px] text-muted">
            Steht im Heimtierausweis, Leerzeichen sind egal.
          </p>
        </div>
      </.form>

      <:footer>
        <.action_button type="submit" form="profile-form" phx-disable-with="Speichert …">
          Speichern
        </.action_button>
      </:footer>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, assign(socket, form: Form.validate(socket.assigns.form, params))}
  end

  def handle_event("save", %{"form" => params}, socket) do
    case store_photo(socket) do
      {:ok, photo_path} ->
        params = if photo_path, do: Map.put(params, "photo_path", photo_path), else: params
        submit(socket, params, photo_path)

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Das Foto konnte nicht gespeichert werden.")}
    end
  end

  defp submit(socket, params, new_photo) do
    old_photo = socket.assigns.profile && socket.assigns.profile.photo_path

    case Form.submit(socket.assigns.form, params: params) do
      {:ok, profile} ->
        if new_photo && old_photo, do: Uploads.delete(old_photo)

        {:noreply,
         socket
         |> put_flash(:info, "Profil von #{profile.name} gespeichert.")
         |> push_navigate(to: ~p"/profil")}

      {:error, form} ->
        if new_photo, do: Uploads.delete(new_photo)
        {:noreply, assign(socket, form: form)}
    end
  end

  defp store_photo(socket) do
    results =
      consume_uploaded_entries(socket, :photo, fn %{path: path}, entry ->
        {:ok, Uploads.store(path, entry.client_name)}
      end)

    case results do
      [] -> {:ok, nil}
      [{:ok, name}] -> {:ok, name}
      [{:error, reason}] -> {:error, reason}
    end
  end

  defp entry_errors(upload), do: Enum.flat_map(upload.entries, &upload_errors(upload, &1))

  defp upload_error(:too_large), do: "Das Foto ist zu groß (höchstens 15 MB)."
  defp upload_error(:not_accepted), do: "Bitte ein Foto als JPG, PNG, WebP oder HEIC wählen."
  defp upload_error(:too_many_files), do: "Bitte nur ein Foto wählen."
  defp upload_error(_), do: "Das Foto konnte nicht hochgeladen werden."
end
