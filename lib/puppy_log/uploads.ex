defmodule PuppyLog.Uploads do
  @moduledoc """
  Stores uploaded files (photos) under a random name in the uploads directory
  (`config :puppy_log, :uploads_dir`, a Docker volume in production).
  """

  @allowed_extensions ~w(.jpg .jpeg .png .webp .heic)
  @name_format ~r/\A[0-9a-f]{32}\.(jpg|jpeg|png|webp|heic)\z/

  @spec allowed_extensions() :: [String.t()]
  def allowed_extensions, do: @allowed_extensions

  @spec dir() :: Path.t()
  def dir, do: Application.fetch_env!(:puppy_log, :uploads_dir)

  @doc "Copies a temporary upload into storage, returns the stored file name."
  @spec store(Path.t(), String.t()) :: {:ok, String.t()} | {:error, term}
  def store(source_path, original_name) do
    extension = original_name |> Path.extname() |> String.downcase()

    if extension in @allowed_extensions do
      name = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower) <> extension

      with :ok <- File.mkdir_p(dir()),
           :ok <- File.cp(source_path, Path.join(dir(), name)) do
        {:ok, name}
      end
    else
      {:error, :unsupported_file_type}
    end
  end

  @doc "Absolute path of a stored file, or :error for names we never generate."
  @spec path(String.t()) :: {:ok, Path.t()} | :error
  def path(name) when is_binary(name) do
    if Regex.match?(@name_format, name), do: {:ok, Path.join(dir(), name)}, else: :error
  end

  @spec delete(String.t() | nil) :: :ok
  def delete(nil), do: :ok

  def delete(name) do
    with {:ok, path} <- path(name), do: File.rm(path)
    :ok
  end
end
