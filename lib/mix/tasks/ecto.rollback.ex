defmodule Mix.Tasks.Ecto.Rollback do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Rolls back the repository migrations"

  @moduledoc """
  Reverts applied migrations in the given repository.

  Migrations are expected at "priv/YOUR_REPO/migrations" directory
  of the current application but it can be configured by specifying
  the `:priv` key under the repository configuration.

  Runs the latest applied migration by default. To roll back to
  a version number, supply `--to version_number`. To roll back a
  specific number of times, use `--step n`. To undo all applied
  migrations, provide `--all`.

  The repositories to rollback are the ones specified under the
  `:ecto_repos` option in the current app configuration. However,
  if the `-r` option is given, it replaces the `:ecto_repos` config.

  If a repository has not yet been started, one will be started outside
  your application supervision tree and shutdown afterwards.

  ## Examples

      mix ecto.rollback
      mix ecto.rollback -r Custom.Repo

      mix ecto.rollback -n 3
      mix ecto.rollback --step 3

      mix ecto.rollback -v 20080906120000
      mix ecto.rollback --to 20080906120000

  ## Command line options

    * `-r`, `--repo` - the repo to rollback
    * `--all` - revert all applied migrations
    * `--step` / `-n` - revert n number of applied migrations
    * `--to` / `-v` - revert all migrations down to and including version
    * `--quiet` - do not log migration commands
    * `--prefix` - the prefix to run migrations on
    * `--pool-size` - the pool size if the repository is started only for the task (defaults to 1)
    * `--log-sql` - log the raw sql migrations are running

  """

  @doc false
  def run(args, migrator \\ &Ecto.Migrator.run/4) do
    repos = parse_repo(args)

    {opts, _, _} = OptionParser.parse args,
      switches: [all: :boolean, step: :integer, to: :integer, start: :boolean,
                 quiet: :boolean, prefix: :string, pool_size: :integer, log_sql: :boolean],
      aliases: [n: :step, v: :to]

    opts =
      if opts[:to] || opts[:step] || opts[:all],
        do: opts,
        else: Keyword.put(opts, :step, 1)

    opts =
      if opts[:quiet],
        do: Keyword.merge(opts, [log: false, log_sql: false]),
        else: opts

    Enum.each repos, fn repo ->
      ensure_repo(repo, args)
      ensure_migrations_path(repo)
      {:ok, pid, apps} = ensure_started(repo, opts)

      pool = repo.config[:pool]
      migrated =
        if function_exported?(pool, :unboxed_run, 2) do
          pool.unboxed_run(repo, fn -> migrator.(repo, migrations_path(repo), :down, opts) end)
        else
          migrator.(repo, migrations_path(repo), :down, opts)
        end

      pid && repo.stop(pid)
      restart_apps_if_migrated(apps, migrated)
    end
  end
end
