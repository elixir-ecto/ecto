defmodule Ecto.Migrator do
  @moduledoc """
  This module provides the migration API.

  ## Example

      defmodule MyApp.MigrationExample do
        use Ecto.Migration

        def up do
          execute "CREATE TABLE users(id serial PRIMARY_KEY, username text)"
        end

        def down do
          execute "DROP TABLE users"
        end
      end

      Ecto.Migrator.up(Repo, 20080906120000, MyApp.MigrationExample)

  """

  require Logger

  alias Ecto.Migration.Runner
  alias Ecto.Migration.SchemaMigration

  @doc """
  Gets all migrated versions.

  This function ensures the migration table exists
  if no table has been defined yet.

  ## Options

    * `:log` - the level to use for logging. Defaults to `:info`.
      Can be any of `Logger.level/0` values or `false`.
    * `:prefix` - the prefix to run the migrations on

  """
  @spec migrated_versions(Ecto.Repo.t, Keyword.t) :: [integer]
  def migrated_versions(repo, opts \\ []) do
    verbose_schema_migration repo, "retrieve migrated versions", fn ->
      SchemaMigration.ensure_schema_migrations_table!(repo, opts[:prefix])
      SchemaMigration.migrated_versions(repo, opts[:prefix])
    end
  end

  @doc """
  Runs an up migration on the given repository.

  ## Options

    * `:log` - the level to use for logging. Defaults to `:info`.
      Can be any of `Logger.level/0` values or `false`.
    * `:prefix` - the prefix to run the migrations on
  """
  @spec up(Ecto.Repo.t, integer, module, Keyword.t) :: :ok | :already_up | no_return
  def up(repo, version, module, opts \\ []) do
    versions = migrated_versions(repo, opts)

    if version in versions do
      :already_up
    else
      do_up(repo, version, module, opts)
      :ok
    end
  end

  defp do_up(repo, version, module, opts) do
    run_maybe_in_transaction repo, module, fn ->
      attempt(repo, module, :forward, :up, :up, opts)
        || attempt(repo, module, :forward, :change, :up, opts)
        || raise Ecto.MigrationError, "#{inspect module} does not implement a `up/0` or `change/0` function"
      verbose_schema_migration repo, "update schema migrations", fn ->
        SchemaMigration.up(repo, version, opts[:prefix])
      end
    end
  end

  @doc """
  Runs a down migration on the given repository.

  ## Options

    * `:log` - the level to use for logging. Defaults to `:info`.
      Can be any of `Logger.level/0` values or `false`.
    * `:prefix` - the prefix to run the migrations on

  """
  @spec down(Ecto.Repo.t, integer, module) :: :ok | :already_down | no_return
  def down(repo, version, module, opts \\ []) do
    versions = migrated_versions(repo, opts)

    if version in versions do
      do_down(repo, version, module, opts)
      :ok
    else
      :already_down
    end
  end

  defp do_down(repo, version, module, opts) do
    run_maybe_in_transaction repo, module, fn ->
      attempt(repo, module, :forward, :down, :down, opts)
        || attempt(repo, module, :backward, :change, :down, opts)
        || raise Ecto.MigrationError, "#{inspect module} does not implement a `down/0` or `change/0` function"
      verbose_schema_migration repo, "update schema migrations", fn ->
        SchemaMigration.down(repo, version, opts[:prefix])
      end
    end
  end

  defp run_maybe_in_transaction(repo, module, fun) do
    cond do
      module.__migration__[:disable_ddl_transaction] ->
        fun.()
      repo.__adapter__.supports_ddl_transaction? ->
        repo.transaction(fun, [log: false, timeout: :infinity])
      true ->
        fun.()
    end
  end

  defp attempt(repo, module, direction, operation, reference, opts) do
    if Code.ensure_loaded?(module) and
       function_exported?(module, operation, 0) do
      Runner.run(repo, module, direction, operation, reference, opts)
      :ok
    end
  end

  @doc """
  Apply migrations to a repository with a given strategy.

  The second argument identifies where the migrations are sourced from. A file
  path may be passed, in which case the migrations will be loaded from this
  during the migration process. The other option is to pass a list of tuples
  that identify the version number and migration modules to be run, for example:

      Ecto.Migrator.run(Repo, [{0, MyApp.Migration1}, {1, MyApp.Migration2}, ...], :up, opts)

  A strategy must be given as an option.

  ## Options

    * `:all` - runs all available if `true`
    * `:step` - runs the specific number of migrations
    * `:to` - runs all until the supplied version is reached
    * `:log` - the level to use for logging. Defaults to `:info`.
      Can be any of `Logger.level/0` values or `false`.
    * `:prefix` - the prefix to run the migrations on

  """
  @spec run(Ecto.Repo.t, binary | [{integer, module}], atom, Keyword.t) :: [integer]
  def run(repo, migration_source, direction, opts) do
    versions = migrated_versions(repo, opts)

    cond do
      opts[:all] ->
        run_all(repo, versions, migration_source, direction, opts)
      to = opts[:to] ->
        run_to(repo, versions, migration_source, direction, to, opts)
      step = opts[:step] ->
        run_step(repo, versions, migration_source, direction, step, opts)
      true ->
        raise ArgumentError, "expected one of :all, :to, or :step strategies"
    end
  end

  @doc """
  Returns an array of tuples as the migration status of the given repo,
  without actually running any migrations.

  """
  def migrations(repo, directory) do
    versions = migrated_versions(repo)

    Enum.map(pending_in_direction(versions, directory, :down) |> Enum.reverse, fn {a, b, _}
     -> {:up, a, b}
    end)
    ++
    Enum.map(pending_in_direction(versions, directory, :up), fn {a, b, _} ->
      {:down, a, b}
    end)
  end

  defp run_to(repo, versions, migration_source, direction, target, opts) do
    within_target_version? = fn
      {version, _, _}, target, :up ->
        version <= target
      {version, _, _}, target, :down ->
        version >= target
    end

    pending_in_direction(versions, migration_source, direction)
    |> Enum.take_while(&(within_target_version?.(&1, target, direction)))
    |> migrate(direction, repo, opts)
  end

  defp run_step(repo, versions, migration_source, direction, count, opts) do
    pending_in_direction(versions, migration_source, direction)
    |> Enum.take(count)
    |> migrate(direction, repo, opts)
  end

  defp run_all(repo, versions, migration_source, direction, opts) do
    pending_in_direction(versions, migration_source, direction)
    |> migrate(direction, repo, opts)
  end

  defp pending_in_direction(versions, migration_source, :up) do
    migrations_for(migration_source)
    |> Enum.filter(fn {version, _name, _file} -> not (version in versions) end)
  end

  defp pending_in_direction(versions, migration_source, :down) do
    migrations_for(migration_source)
    |> Enum.filter(fn {version, _name, _file} -> version in versions end)
    |> Enum.reverse
  end

  # This function will match directories passed into `Migrator.run`.
  defp migrations_for(migration_source) when is_binary(migration_source) do
    query = Path.join(migration_source, "*")

    for entry <- Path.wildcard(query),
        info = extract_migration_info(entry),
        do: info
  end

  # This function will match specific version/modules passed into `Migrator.run`.
  defp migrations_for(migration_source) when is_list(migration_source) do
    Enum.map migration_source, fn({version, module}) -> {version, module, :existing_module} end
  end

  defp extract_migration_info(file) do
    base = Path.basename(file)
    ext  = Path.extname(base)

    case Integer.parse(Path.rootname(base)) do
      {integer, "_" <> name} when ext == ".exs" ->
        {integer, name, file}
      _ ->
        nil
    end
  end

  defp migrate([], direction, _repo, opts) do
    level = Keyword.get(opts, :log, :info)
    log(level, "Already #{direction}")
    []
  end

  defp migrate(migrations, direction, repo, opts) do
    ensure_no_duplication(migrations)

    Enum.map migrations, fn {version, name_or_mod, file} ->
      mod = extract_module(file, name_or_mod)
      case direction do
        :up   -> do_up(repo, version, mod, opts)
        :down -> do_down(repo, version, mod, opts)
      end
      version
    end
  end

  defp ensure_no_duplication([{version, name, _} | t]) do
    if List.keyfind(t, version, 0) do
      raise Ecto.MigrationError,
            "migrations can't be executed, migration version #{version} is duplicated"
    end

    if List.keyfind(t, name, 1) do
      raise Ecto.MigrationError,
            "migrations can't be executed, migration name #{name} is duplicated"
    end

    ensure_no_duplication(t)
  end

  defp ensure_no_duplication([]), do: :ok

  defp is_migration_module?({mod, _bin}), do: function_exported?(mod, :__migration__, 0)
  defp is_migration_module?(mod), do: function_exported?(mod, :__migration__, 0)

  defp extract_module(:existing_module, mod) do
    if is_migration_module?(mod), do: mod, else: raise_no_migration_in_module(mod)
  end
  defp extract_module(file, _name) do
    modules = Code.load_file(file)
    case Enum.find(modules, &is_migration_module?/1) do
      {mod, _bin} -> mod
      _otherwise -> raise_no_migration_in_file(file)
    end
  end

  defp verbose_schema_migration(repo, reason, fun) do
    try do
      fun.()
    rescue
      error ->
        Logger.error """
        Could not #{reason}. This error usually happens due to the following:

          * The database does not exist
          * The "schema_migrations" table, which Ecto uses for managing
            migrations, was defined by another library

        To fix the first issue, run "mix ecto.create".

        To address the second, you can run "mix ecto.drop" followed by
        "mix ecto.create". Alternatively you may configure Ecto to use
        another table for managing migrations:

            config #{inspect repo.config[:otp_app]}, #{inspect repo},
              migration_source: "some_other_table_for_schema_migrations"

        The full error report is shown below.
        """
        reraise error, System.stacktrace
    end
  end

  defp raise_no_migration_in_file(file) do
    raise Ecto.MigrationError,
          "file #{Path.relative_to_cwd(file)} is not an Ecto.Migration"
  end
  defp raise_no_migration_in_module(mod) do
    raise Ecto.MigrationError,
          "module #{inspect mod} is not an Ecto.Migration"
  end

  defp log(false, _msg), do: :ok
  defp log(level, msg),  do: Logger.log(level, msg)
end
