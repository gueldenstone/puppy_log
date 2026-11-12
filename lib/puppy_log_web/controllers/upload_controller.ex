defmodule PuppyLogWeb.UploadController do
  @moduledoc "Serves uploaded photos to signed-in household members only."

  use PuppyLogWeb, :controller

  def show(%{assigns: %{current_user: %{}}} = conn, %{"name" => name}) do
    with {:ok, path} <- PuppyLog.Uploads.path(name),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type(MIME.from_path(path), nil)
      |> put_resp_header("cache-control", "private, max-age=31536000, immutable")
      |> send_file(200, path)
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  def show(conn, _params), do: send_resp(conn, 401, "")
end
