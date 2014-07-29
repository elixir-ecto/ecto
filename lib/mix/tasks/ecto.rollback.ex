defmodule Mix.Tasks.Ecto.Rollback do
  use Mix.Task
  import Mix.Tasks.Ecto

  @shortdoc "Reverts migrations down on a repo"

  @moduledoc """
  Reverts applied migrations in the given repository.

  Migrations are expected to be found inside the migrations
  directory returned by the priv function defined in the
  repository.

  Runs the latest applied migration by default. To roll back to
  to a version number, supply `--to version_number`.
  To roll back a specific number of times, use `--step n`.
  To undo all applied migrations, provide `--all`.

  ## Command line options

  * `--all` - revert all applied migrations
  * `--step` / `-n` - rever n number of applied migrations
  * `--to` / `-v` - revert all migrations down to and including version
  * `--no-start` - do not start applications

  ## Examples

      mix ecto.rollback MyApp.Repo

      mix ecto.rollback MyApp.Repo -n 3
      mix ecto.rollback MyApp.Repo --step 3

      mix ecto.rollback MyApp.Repo -v 20080906120000
      mix ecto.rollback MyApp.Repo --to 20080906120000

  """
  def run(args, migrator \\ &Ecto.Migrator.run/4) do
    Mix.Task.run "app.start", args

    {opts, args, _} = OptionParser.parse args,
      switches: [all: :boolean, step: :integer, to: :integer],
      aliases: [n: :step, v: :to]

    {repo, _} = parse_repo(args)
    ensure_repo(repo)
    if opts[:no_start], do: ensure_started(repo)

    unless opts[:to] || opts[:step] || opts[:all] do
      opts = Keyword.put(opts, :step, 1)
    end

    migrator.(repo, migrations_path(repo), :down, opts)
  end
end
