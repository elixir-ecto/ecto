defmodule Ecto.Migrator do
  @moduledoc """
  This module provides the migration API.

  ## Example

      defmodule MyApp.MigrationExample do
        use Ecto.Migration

        def up do
          "CREATE TABLE users(id serial PRIMARY_KEY, username text)"
        end

        def down do
          "DROP TABLE users"
        end
      end

      Ecto.Migrator.up(Repo, 20080906120000, MyApp.MigrationExample)

  """
  require Logger

  @type strategy :: [all: true, to: non_neg_integer, step: non_neg_integer, logger: ((:up|:down, String.t) -> any)]

  @doc """
  Runs an up migration on the given repository.
  """
  @spec up(Ecto.Repo.t, integer, Module.t) :: :ok | :already_up | no_return
  def up(repo, version, module) do
    commands = List.wrap(module.up)
    repo.adapter.migrate_up(repo, version, commands)
  end

  @doc """
  Runs a down migration on the given repository.
  """
  @spec down(Ecto.Repo.t, integer, Module.t) :: :ok | :missing_up | no_return
  def down(repo, version, module) do
    commands = List.wrap(module.down)
    repo.adapter.migrate_down(repo, version, commands)
  end

  @doc """
  Apply migrations in a directory to a repository with given strategy.

  A strategy must be pass as an option. The available strategy types are:

  * `:all`    runs all available if `true`
  * `:step`   runs the specific number of migrations
  * `:to`     runs all until the supplied version is reached
  * `:logger` specifies a custom migration logger function ((:up|:down, String.t) -> any),
              defaults to a simple Logger.info wrapper

  """
  @spec run(Ecto.Repo.t, binary, atom, strategy) :: [integer]
  def run(repo, directory, direction, opts) do
    cond do
      opts[:all] ->
        run_all(repo, directory, direction, opts[:logger] || &migration_logger/2)
      to = opts[:to] ->
        run_to(repo, directory, direction, to, opts[:logger] || &migration_logger/2)
      step = opts[:step] ->
        run_step(repo, directory, direction, step, opts[:logger] || &migration_logger/2)
      true ->
        raise ArgumentError, message: "expected one of :all, :to, or :step strategies"
    end
  end

  defp run_to(repo, directory, direction, target, logfn) do
    within_target_version? = fn
      {version, _}, target, :up ->
        version <= target
      {version, _}, target, :down ->
        version >= target
    end

    pending_in_direction(repo, directory, direction)
      |> Enum.take_while(&(within_target_version?.(&1, target, direction)))
      |> migrate(direction, repo, logfn)
  end

  defp run_step(repo, directory, direction, count, logfn) do
    pending_in_direction(repo, directory, direction)
      |> Enum.take(count)
      |> migrate(direction, repo, logfn)
  end

  defp run_all(repo, directory, direction, logfn) do
    pending_in_direction(repo, directory, direction)
      |> migrate(direction, repo, logfn)
  end

  defp pending_in_direction(repo, directory, :up) do
    versions = repo.adapter.migrated_versions(repo)
    migrations_for(directory) |>
      Enum.filter(fn {version, _file} ->
        not (version in versions)
      end)
  end

  defp pending_in_direction(repo, directory, :down) do
    versions = repo.adapter.migrated_versions(repo)
    migrations_for(directory) |>
      Enum.filter(fn {version, _file} ->
        version in versions
      end)
      |> :lists.reverse
  end

  defp migrations_for(directory) do
    Path.join(directory, "*")
      |> Path.wildcard
      |> Enum.filter(&Regex.match?(~r"\d+_.+\.exs$", &1))
      |> attach_versions
  end

  defp attach_versions(files) do
    Enum.map(files, fn(file) ->
      {integer, _} = Integer.parse(Path.basename(file))
      {integer, file}
    end)
  end

  defp migration_logger(:up, file)  do
    Logger.info "Ecto migration running UP #{file}"
  end

  defp migration_logger(:down, file)  do
    Logger.info "Ecto migration running DOWN #{file}"
  end

  defp migrate(migrations, direction, repo, logfn) do
    ensure_no_duplication(migrations)

    Enum.map migrations, fn {version, file} ->
      {mod, _bin} =
        Enum.find(Code.load_file(file), fn {mod, _bin} ->
          function_exported?(mod, :__migration__, 0)
        end) || raise_no_migration_in_file(file)

      file = Path.relative_to_cwd(file)
      logfn.(direction, file)
      case direction do
        :up ->
          up(repo, version, mod)
        :down ->
          down(repo, version, mod)
      end

      version
    end
  end

  defp ensure_no_duplication([{version, _} | t]) do
    if List.keyfind(t, version, 0) do
      raise Ecto.MigrationError, message: "migrations can't be executed, version #{version} is duplicated"
    else
      ensure_no_duplication(t)
    end
  end

  defp ensure_no_duplication([]), do: :ok

  defp raise_no_migration_in_file(file) do
    raise Ecto.MigrationError, message: "file #{Path.relative_to_cwd(file)} does not contain any Ecto.Migration"
  end
end
