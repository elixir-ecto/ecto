defmodule Mix.Tasks.Ecto.Migrate do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Runs the repository migrations"

  @moduledoc """
  Runs the pending migrations for the given repository.

  Migrations are expected at "priv/YOUR_REPO/migrations" directory
  of the current application but it can be configured to be any
  subdirectory of `priv` by specifying the `:priv` key under the
  repository configuration.

  Runs all pending migrations by default. To migrate up to a specific
  version number, supply `--to version_number`. To migrate a specific
  number of times, use `--step n`.

  The repositories to migrate are the ones specified under the
  `:ecto_repos` option in the current app configuration. However,
  if the `-r` option is given, it replaces the `:ecto_repos` config.

  Since Ecto tasks can only be executed once, if you need to migrate
  multiple repositories, set `:ecto_repos` accordingly or pass the `-r`
  flag multiple times.

  If a repository has not yet been started, one will be started outside
  your application supervision tree and shutdown afterwards.

  ## Examples

      mix ecto.migrate
      mix ecto.migrate -r Custom.Repo

      mix ecto.migrate -n 3
      mix ecto.migrate --step 3

      mix ecto.migrate -v 20080906120000
      mix ecto.migrate --to 20080906120000

  ## Command line options

    * `-r`, `--repo` - the repo to migrate
    * `--all` - run all pending migrations
    * `--step` / `-n` - run n number of pending migrations
    * `--to` / `-v` - run all migrations up to and including version
    * `--quiet` - do not log migration commands
    * `--prefix` - the prefix to run migrations on
    * `--pool-size` - the pool size if the repository is started only for the task (defaults to 1)
    * `--log-sql` - log the raw sql migrations are running

  """

  @doc false
  def run(args, migrator \\ &Ecto.Migrator.run/4) do
    repos = parse_repo(args)

    {opts, _, _} = OptionParser.parse args,
      switches: [all: :boolean, step: :integer, to: :integer, quiet: :boolean,
                 prefix: :string, pool_size: :integer, log_sql: :boolean],
      aliases: [n: :step, v: :to]

    opts =
      if opts[:to] || opts[:step] || opts[:all],
        do: opts,
        else: Keyword.put(opts, :all, true)

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
          pool.unboxed_run(repo, fn -> migrator.(repo, migrations_path(repo), :up, opts) end)
        else
          migrator.(repo, migrations_path(repo), :up, opts)
        end

      pid && repo.stop(pid)
      restart_apps_if_migrated(apps, migrated)
    end
  end
end
