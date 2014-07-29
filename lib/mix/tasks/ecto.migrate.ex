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

  ## Command line options

  * `--all` - run all pending migrations
  * `--step` / `-n` - run n number of pending migrations
  * `--to` / `-v` - run all migrations up to and including version
  * `--no-start` - do not start applications

  ## Examples

      mix ecto.migrate MyApp.Repo

      mix ecto.migrate MyApp.Repo -n 3
      mix ecto.migrate MyApp.Repo --step 3

      mix ecto.migrate MyApp.Repo -v 20080906120000
      mix ecto.migrate MyApp.Repo --to 20080906120000

  """
  def run(args, migrator \\ &Ecto.Migrator.run/4) do
    Mix.Task.run "app.start", args

    {opts, args, _} = OptionParser.parse args,
      switches: [all: :boolean, step: :integer, to: :integer, start: :boolean],
      aliases: [n: :step, v: :to]

    {repo, _} = parse_repo(args)
    ensure_repo(repo)
    unless opts[:start], do: ensure_started(repo)

    unless opts[:to] || opts[:step] || opts[:all] do
      opts = Keyword.put(opts, :all, true)
    end

    migrator.(repo, migrations_path(repo), :up, opts)
  end
end
