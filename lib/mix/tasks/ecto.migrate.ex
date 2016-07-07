defmodule Mix.Tasks.Ecto.Migrate do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Runs the repository migrations"
  @recursive true

  @moduledoc """
  Runs the pending migrations for the given repository.

  The repository must be set under `:ecto_repos` in the
  current app configuration or given via the `-r` option.

  By default, migrations are expected at "priv/YOUR_REPO/migrations"
  directory of the current application but it can be configured
  to be any subdirectory of `priv` by specifying the `:priv` key
  under the repository configuration.

  Runs all pending migrations by default. To migrate up
  to a version number, supply `--to version_number`.
  To migrate up a specific number of times, use `--step n`.

  If the repository has not been started yet, one will be
  started outside our application supervision tree and shutdown
  afterwards.

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

  """

  @doc false
  def run(args, migrator \\ &Ecto.Migrator.run/4) do
    repos = parse_repo(args)

    {opts, _, _} = OptionParser.parse args,
      switches: [all: :boolean, step: :integer, to: :integer, quiet: :boolean,
                 prefix: :string, pool_size: :integer],
      aliases: [n: :step, v: :to]

    opts =
      if opts[:to] || opts[:step] || opts[:all],
        do: opts,
        else: Keyword.put(opts, :all, true)

    opts =
      if opts[:quiet],
        do: Keyword.put(opts, :log, false),
        else: opts

    Enum.each repos, fn repo ->
      ensure_repo(repo, args)
      ensure_migrations_path(repo)
      {:ok, pid, apps} = ensure_started(repo, opts)
      sandbox? = repo.config[:pool] == Ecto.Adapters.SQL.Sandbox

      # If the pool is Ecto.Adapters.SQL.Sandbox,
      # let's make sure we get a connection outside of a sandbox.
      if sandbox? do
        Ecto.Adapters.SQL.Sandbox.checkin(repo)
        Ecto.Adapters.SQL.Sandbox.checkout(repo, sandbox: false)
      end

      migrated =
        try do
          migrator.(repo, migrations_path(repo), :up, opts)
        after
          sandbox? && Ecto.Adapters.SQL.Sandbox.checkin(repo)
        end

      pid && repo.stop(pid)
      restart_apps_if_migrated(apps, migrated)
    end
  end
end
