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
    SchemaMigration.ensure_schema_migrations_table!(repo, opts[:prefix])
    SchemaMigration.migrated_versions(repo, opts[:prefix])
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
      SchemaMigration.up(repo, version, opts[:prefix])
    end
  end

  @doc """
  Runs a down migration on the given repository.

  ## Options

    * `:log` - the level to use for logging. Defaults to `:info`.
      Can be any of `Logger.level/0` values or `false`.

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
      SchemaMigration.down(repo, version, opts[:prefix])
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
  Apply migrations in a directory to a repository with given strategy.

  A strategy must be given as an option.

  ## Options

    * `:all` - runs all available if `true`
    * `:step` - runs the specific number of migrations
    * `:to` - runs all until the supplied version is reached
    * `:log` - the level to use for logging. Defaults to `:info`.
      Can be any of `Logger.level/0` values or `false`.

  """
  @spec run(Ecto.Repo.t, binary, atom, Keyword.t) :: [integer]
  def run(repo, directory, direction, opts) do
    versions = migrated_versions(repo, opts)

    cond do
      opts[:all] ->
        run_all(repo, versions, directory, direction, opts)
      to = opts[:to] ->
        run_to(repo, versions, directory, direction, to, opts)
      step = opts[:step] ->
        run_step(repo, versions, directory, direction, step, opts)
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

  defp run_to(repo, versions, directory, direction, target, opts) do
    within_target_version? = fn
      {version, _, _}, target, :up ->
        version <= target
      {version, _, _}, target, :down ->
        version >= target
    end

    pending_in_direction(versions, directory, direction)
    |> Enum.take_while(&(within_target_version?.(&1, target, direction)))
    |> migrate(direction, repo, opts)
  end

  defp run_step(repo, versions, directory, direction, count, opts) do
    pending_in_direction(versions, directory, direction)
    |> Enum.take(count)
    |> migrate(direction, repo, opts)
  end

  defp run_all(repo, versions, directory, direction, opts) do
    pending_in_direction(versions, directory, direction)
    |> migrate(direction, repo, opts)
  end

  defp pending_in_direction(versions, directory, :up) do
    migrations_for(directory)
    |> Enum.filter(fn {version, _name, _file} -> not (version in versions) end)
  end

  defp pending_in_direction(versions, directory, :down) do
    migrations_for(directory)
    |> Enum.filter(fn {version, _name, _file} -> version in versions end)
    |> Enum.reverse
  end

  defp migrations_for(directory) do
    query = Path.join(directory, "*")

    for entry <- Path.wildcard(query),
        info = extract_migration_info(entry),
        do: info
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

    Enum.map migrations, fn {version, _name, file} ->
      {mod, _bin} =
        Enum.find(Code.load_file(file), fn {mod, _bin} ->
          function_exported?(mod, :__migration__, 0)
        end) || raise_no_migration_in_file(file)

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

  defp raise_no_migration_in_file(file) do
    raise Ecto.MigrationError,
          "file #{Path.relative_to_cwd(file)} does not contain any Ecto.Migration"
  end

  defp log(false, _msg), do: :ok
  defp log(level, msg),  do: Logger.log(level, msg)
end
