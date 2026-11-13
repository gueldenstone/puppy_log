defmodule PuppyLog.Release do
  @moduledoc """
  Tasks for the production release, where Mix is not available.

      bin/puppy_log eval "PuppyLog.Release.migrate()"
  """
  @app :PuppyLog

  def migrate do
    load_app()

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  defp load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
