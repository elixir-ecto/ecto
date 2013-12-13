defmodule Ecto.Migrator do
  @moduledoc """
  This module provides the migration API.

  ## Example

      defmodule MyApp.MigrationExample do
        use Ecto.Migration

        def up do
          "CREATE TABLE user(id serial PRIMARY_KEY, username text)"
        end

        def down do
          "DROP TABLE user"
        end
      end

      Ecto.Migrator.up(Repo, 20080906120000, MyApp.MigrationExample)

  """

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

  @doc false
  def run_all(repo, directory) do
    IO.write "Ecto.Migrator.run_all/2 is deprecated, please use Ecto.Migrator.run/3 instead."
    run repo, directory
  end

  @doc """
  Apply migrations in a directory to a repository.

  Available options are:
  - `direction:` `:up` or `:down`
                  defaults to :up

  - `all:`  runs all available if `true`
  - `step:` runs a specific number of migrations
  - `to:`   runs all until supplied version is reached

  If `:all`, `:step`, or `:to` are not provided, the direction
  determines the default migration strategy:

  - `up:`   runs with `all: true`
  - `down:` runs with `step: 1`

  If more than one stragegy is provided, it will conservatively favor
  the most explicit strategy: it will run `:to` a migration,
  before it `:steps` through migrations, before it runs `:all`.
  """
  @spec run(Ecto.Repo.t, binary, Keyword.t) :: [integer]
  def run(repo, directory, opts // []) do
    { direction, strategy } = parse_opts(opts)
    do_run repo, directory, direction, strategy
  end

  # To extend Migrator.run with different strategies,
  # define a `do_run` clause that matches on it
  # and insert the strategy type into the `strategies` function below.

  defp do_run(repo, directory, direction, {:to, target_version}) do
    within_target_version? = fn
      { version, _ }, target, :up ->
        version <= target
      { version, _ }, target, :down ->
        version >= target
    end
    pending_in_direction(repo, directory, direction)
      |> Enum.take_while(&(within_target_version?.(&1, target_version, direction)))
      |> migrate(direction, repo)
  end

  defp do_run(repo, directory, direction, {:step, count}) do
    pending_in_direction(repo, directory, direction)
      |> Enum.take(count)
      |> migrate(direction, repo)
  end

  defp do_run(repo, directory, direction, {:all, true}) do
    pending_in_direction(repo, directory, direction)
      |> migrate(direction, repo)
  end

  # Keep in order of precedence.
  defp strategies, do: [:to, :step, :all]

  defp parse_opts(opts) do
    { direction, opts } = Keyword.pop(opts, :direction, :up)
    { direction, strategy_from(opts) || default_strategy_for(direction) }
  end

  defp strategy_from([]), do: nil
  defp strategy_from([strategy]) do
    if strategy |> elem(0) |> Kernel.in(strategies) do
      strategy
    end
  end
  defp strategy_from(opts) do
    opts
      |> Enum.filter(&(&1 |> elem(0) |> Kernel.in(strategies)))
      |> Enum.sort(&(strategy_precedence(&1) > strategy_precedence(&2)))
      |> Enum.first
  end

  defp strategy_precedence({ strategy, _ }) do
    strategies
      |> :lists.reverse
      |> Enum.find_index(&(&1 == strategy))
  end

  defp default_strategy_for(:up),    do: { :all, true }
  defp default_strategy_for(:down),  do: { :step, 1 }

  defp pending_in_direction(repo, directory, :up) do
    versions = repo.adapter.migrated_versions(repo)
    migrations_for(directory) |>
      Enum.filter(fn { version, _file } ->
        not (version in versions)
      end)
  end

  defp pending_in_direction(repo, directory, :down) do
    versions = repo.adapter.migrated_versions(repo)
    migrations_for(directory) |>
      Enum.filter(fn { version, _file } ->
        version in versions
      end)
      |> :lists.reverse
  end

  defp migrations_for(directory) do
    Path.join(directory, "*")
      |> Path.wildcard
      |> Enum.filter(&Regex.match?(%r"\d+_.+\.exs$", &1))
      |> attach_versions
  end

  defp attach_versions(files) do
    Enum.map(files, fn(file) ->
      { integer, _ } = Integer.parse(Path.basename(file))
      { integer, file }
    end)
  end

  defp migrate(migrations, direction, repo) do
    ensure_no_duplication(migrations)
    migrator = case direction do
      :up -> &up/3
      :down -> &down/3
    end

    Enum.map migrations, fn { version, file } ->
      { mod, _bin } =
        Enum.find(Code.load_file(file), fn { mod, _bin } ->
          function_exported?(mod, :__migration__, 0)
        end) || raise_no_migration_in_file(file)

      migrator.(repo, version, mod)
      version
    end
  end

  defp ensure_no_duplication([{ version, _ } | t]) do
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
