defmodule Mix.Tasks.Ecto.Migrate do
  use Mix.Task
  import Mix.Tasks.Ecto

  @shortdoc "Runs the given repo migrations"

  @moduledoc """
  Runs the pending migrations for the given repository.
  Migrations are expected to be found inside the migrations
  directory returned by the priv function defined in the
  repository.

  ## Examples

      mix ecto.migrate MyApp.Repo

  """
  def run(args, migrator // &Ecto.Migrator.run_up/2) do
    { repo, _ } = parse_repo(args)
    ensure_started(repo)
    migrator.(repo, migrations_path(repo))
  end
end
