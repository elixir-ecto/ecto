defmodule Mix.Tasks.Ecto.Migrate do
  use Mix.Task
  import Mix.Tasks.Ecto

  @shortdoc "Runs migrations up on a repo"

  @moduledoc """
  Runs the pending migrations for the given repository.

  Migrations are expected to be found inside the migrations
  directory returned by the priv function defined in the
  repository.

  Runs all pending migrations by default. To migrate up
  to a version number, supply `--to version_number`.
  To migrate up a specific number of times, use `--step n`.

  ## Examples

      mix ecto.migrate MyApp.Repo

      mix ecto.migrate MyApp.Repo -n 3
      mix ecto.migrate MyApp.Repo --step 3

      mix ecto.migrate MyApp.Repo -v 20080906120000
      mix ecto.migrate MyApp.Repo --to 20080906120000

  """
  def run(args, migrator // &Ecto.Migrator.run/4) do
    { opts, args, _ } = OptionParser.parse args,
      switches: [all: :boolean, step: :integer, version: :integer],
      aliases: [n: :step, v: :to]
    { repo, _ } = parse_repo(args)
    ensure_repo(repo)
    ensure_started(repo)
    { strategy, _ } = parse_strategy(opts) # We don't use other opts atm
    migrator.(repo, migrations_path(repo), :up, strategy || { :all, true })
  end
end
