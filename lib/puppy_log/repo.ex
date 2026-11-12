defmodule PuppyLog.Repo do
  use AshSqlite.Repo,
    otp_app: :puppy_log

  # Let Ash wrap write actions in a transaction, so a multi-step action
  # rolls back as a unit. Requires a non-zero `busy_timeout`, which the
  # driver sets by default.
  @impl true
  def write_transactions?, do: true

  # SQLite is bundled with exqlite, so the version is known.
  @impl true
  def min_sqlite_version, do: %Version{major: 3, minor: 53, patch: 4}
end
