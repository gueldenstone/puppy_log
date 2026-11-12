defmodule PuppyLogWeb.UploadControllerTest do
  use PuppyLogWeb.ConnCase, async: false

  alias PuppyLog.Uploads

  setup do
    source = Path.join(System.tmp_dir!(), "puppy-test-#{System.unique_integer([:positive])}.jpg")
    File.write!(source, "fake jpeg")
    on_exit(fn -> File.rm(source) end)

    {:ok, name} = Uploads.store(source, "IMG_0001.JPG")
    on_exit(fn -> Uploads.delete(name) end)

    %{name: name}
  end

  test "serves photos to signed-in members", %{conn: conn, name: name} do
    %{conn: conn} = register_and_sign_in(%{conn: conn})
    conn = get(conn, ~p"/uploads/#{name}")

    assert response(conn, 200) == "fake jpeg"
    assert response_content_type(conn, :jpg) =~ "image/jpeg"
  end

  test "rejects anonymous requests", %{conn: conn, name: name} do
    assert conn |> get(~p"/uploads/#{name}") |> response(401)
  end

  test "only serves names we generated", %{conn: conn} do
    %{conn: conn} = register_and_sign_in(%{conn: conn})
    assert conn |> get("/uploads/..%2Fpuppy_log_test.db") |> response(404)
    assert conn |> get(~p"/uploads/#{String.duplicate("a", 32) <> ".jpg"}") |> response(404)
  end

  test "store rejects other file types" do
    assert {:error, :unsupported_file_type} = Uploads.store("/etc/hosts", "hosts.sh")
  end
end
