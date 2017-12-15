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
    end

    lock_for_migrations repo, opts, fn versions -> versions end
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
    verbose_schema_migration repo, "create schema migrations table", fn ->
      SchemaMigration.ensure_schema_migrations_table!(repo, opts[:prefix])
    end

    lock_for_migrations repo, opts, fn versions ->
      if version in versions do
        :already_up
      else
        do_up(repo, version, module, opts)
      end
    end
  end

  defp do_up(repo, version, module, opts) do
    run_maybe_in_transaction(repo, module, fn ->
      attempt(repo, module, :forward, :up, :up, opts)
        || attempt(repo, module, :forward, :change, :up, opts)
        || {:error, Ecto.MigrationError.exception(
            "#{inspect module} does not implement a `up/0` or `change/0` function")}
    end)
    |> case do
      :ok ->
        verbose_schema_migration repo, "update schema migrations", fn ->
          SchemaMigration.up(repo, version, opts[:prefix])
        end
        :ok
      error ->
        error
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
    verbose_schema_migration repo, "create schema migrations table", fn ->
      SchemaMigration.ensure_schema_migrations_table!(repo, opts[:prefix])
    end

    lock_for_migrations repo, opts, fn versions ->
      if version in versions do
        do_down(repo, version, module, opts)
      else
        :already_down
      end
    end
  end

  defp do_down(repo, version, module, opts) do
    run_maybe_in_transaction(repo, module, fn ->
      attempt(repo, module, :forward, :down, :down, opts)
        || attempt(repo, module, :backward, :change, :down, opts)
        || {:error, Ecto.MigrationError.exception(
            "#{inspect module} does not implement a `down/0` or `change/0` function")}
    end)
    |> case do
      :ok ->
        verbose_schema_migration repo, "update schema migrations", fn ->
          SchemaMigration.down(repo, version, opts[:prefix])
        end
        :ok
      error ->
        error
    end
  end

  defp run_maybe_in_transaction(repo, module, fun) do
    Task.async(fn ->
      do_run_maybe_in_transaction(repo, module, fun)
    end)
    |> Task.await(:infinity)
  end

  defp do_run_maybe_in_transaction(repo, module, fun) do
    cond do
      module.__migration__[:disable_ddl_transaction] ->
        fun.()
      repo.__adapter__.supports_ddl_transaction? ->
        {:ok, result} = repo.transaction(fun, [log: false, timeout: :infinity])
        result
      true ->
        fun.()
    end
  catch kind, reason ->
    {kind, reason, System.stacktrace}
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
    verbose_schema_migration repo, "create schema migrations table", fn ->
      SchemaMigration.ensure_schema_migrations_table!(repo, opts[:prefix])
    end

    lock_for_migrations repo, opts, fn versions ->
      cond do
        opts[:all] ->
          run_all(repo, versions, migration_source, direction, opts)
        to = opts[:to] ->
          run_to(repo, versions, migration_source, direction, to, opts)
        step = opts[:step] ->
          run_step(repo, versions, migration_source, direction, step, opts)
        true ->
          {:error, ArgumentError.exception("expected one of :all, :to, or :step strategies")}
      end
    end
  end

  @doc """
  Returns an array of tuples as the migration status of the given repo,
  without actually running any migrations.

  """
  def migrations(repo, directory) do
    repo
    |> migrated_versions
    |> collect_migrations(directory)
    |> Enum.sort_by(fn {_, version, _} -> version end)
  end

  defp lock_for_migrations(repo, opts, fun) do
    query = SchemaMigration.versions(repo, opts[:prefix])

    case repo.__adapter__.lock_for_migrations(repo, query, opts, fun) do
      {kind, reason, stacktrace} ->
        :erlang.raise(kind, reason, stacktrace)
      {:error, error} ->
        raise error
      result ->
        result
    end
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

  defp collect_migrations(versions, migration_source) do
    ups_with_file =
      versions
      |> pending_in_direction(migration_source, :down)
      |> Enum.map(fn {version, name, _} -> {:up, version, name} end)

    ups_without_file =
      versions
      |> versions_without_file(migration_source)
      |> Enum.map(fn version -> {:up, version, "** FILE NOT FOUND **"} end)

    downs =
      versions
      |> pending_in_direction(migration_source, :up)
      |> Enum.map(fn {version, name, _} -> {:down, version, name} end)

    ups_with_file ++ ups_without_file ++ downs
  end

  defp versions_without_file(versions, migration_source) do
    versions_with_file =
      migration_source
      |> migrations_for
      |> Enum.map(&elem(&1, 0))

    versions -- versions_with_file
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
    with :ok <- ensure_no_duplication(migrations),
         versions when is_list(versions) <- do_migrate(migrations, direction, repo, opts),
         do: Enum.reverse(versions)
  end

  defp do_migrate(migrations, direction, repo, opts) do
    Enum.reduce_while migrations, [], fn {version, name_or_mod, file}, versions ->
      with {:ok, mod} <- extract_module(file, name_or_mod),
           :ok <- do_direction(direction, repo, version, mod, opts) do
        {:cont, [version | versions]}
      else
        error ->
          {:halt, error}
      end
    end
  end

  defp do_direction(:up, repo, version, mod, opts) do
    do_up(repo, version, mod, opts)
  end
  defp do_direction(:down, repo, version, mod, opts) do
    do_down(repo, version, mod, opts)
  end

  defp ensure_no_duplication([{version, name, _} | t]) do
    cond do
      List.keyfind(t, version, 0) ->
        {:error, Ecto.MigrationError.exception(
          "migrations can't be executed, migration version #{version} is duplicated")}
      List.keyfind(t, name, 1) ->
        {:error, Ecto.MigrationError.exception(
          "migrations can't be executed, migration name #{name} is duplicated")}
      true ->
        ensure_no_duplication(t)
    end
  end
  defp ensure_no_duplication([]), do: :ok

  defp is_migration_module?({mod, _bin}), do: function_exported?(mod, :__migration__, 0)
  defp is_migration_module?(mod), do: function_exported?(mod, :__migration__, 0)

  defp extract_module(:existing_module, mod) do
    if is_migration_module?(mod) do
      {:ok, mod}
    else
      {:error, Ecto.MigrationError.exception(
        "module #{inspect mod} is not an Ecto.Migration")}
    end
  end
  defp extract_module(file, _name) do
    modules = Code.load_file(file)
    case Enum.find(modules, &is_migration_module?/1) do
      {mod, _bin} -> {:ok, mod}
      _otherwise -> {:error, Ecto.MigrationError.exception(
                      "file #{Path.relative_to_cwd(file)} is not an Ecto.Migration")}
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

  defp log(false, _msg), do: :ok
  defp log(level, msg),  do: Logger.log(level, msg)
end
