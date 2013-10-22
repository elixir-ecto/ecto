defmodule Ecto.Migrator do
  @moduledoc """
  This module provides the migration API.

  ## Example

      defmodule MyApp.MigrationExample do
        use Ecto.Migration

        def up do
          "CREATE TABLE user(id serial PRIMARY_KEY, username varchar(25));"
        end

        def down do
          "DROP TABLE user;"
        end
      end

      Ecto.Migrator.up(Repo, 20080906120000, MyApp.MigrationExample)

  """

  @doc """
  Runs an up migration on the given repository.
  """
  def up(repo, version, module) do
    repo.adapter.migrate_up(repo, version, module.up)
  end

  @doc """
  Runs a down migration on the given repository.
  """
  def down(repo, version, module) do
    repo.adapter.migrate_down(repo, version, module.down)
  end

  @doc """
  Runs all migrations in the given directory.
  """
  @spec run_up(Ecto.Repo.t, binary) :: [integer] | no_return
  def run_up(repo, directory) do
    migrations = Path.join(directory, "*")
                 |> Path.wildcard
                 |> Enum.filter(&Regex.match?(%r"\d+_.+\.exs$", &1))
                 |> attach_versions

    ensure_no_duplication(migrations)

    migrations
    |> filter_migrated(repo)
    |> execute_migrations(repo)
  end

  defp attach_versions(files) do
    Enum.map(files, fn(file) ->
      { integer, _ } = Integer.parse(Path.basename(file))
      { integer, file }
    end)
  end

  defp ensure_no_duplication([{ version, _ } | t]) do
    if List.keyfind(t, version, 0) do
      raise Ecto.MigrationError, message: "migrations can't be executed, version #{version} is duplicated"
    else
      ensure_no_duplication(t)
    end
  end

  defp ensure_no_duplication([]), do: :ok

  defp filter_migrated(migrations, repo) do
    case repo.adapter.migrated_versions(repo) do
      { :error, error } ->
        raise Ecto.MigrationError, message: "could not migrate, got: #{inspect error}"
      { :ok, versions } ->
        Enum.filter(migrations, fn { version, _file } ->
          not (version in versions)
        end)
    end
  end

  defp execute_migrations(migrations, repo) do
    Enum.map migrations, fn { version, file } ->
      { mod, _bin } =
        Enum.find(Code.load_file(file), fn { mod, _bin } ->
          function_exported?(mod, :__migration__, 0)
        end) || raise_no_migration_in_file(file)

      case repo.adapter.migrate_up(repo, version, mod.up) do
        { :error, error } ->
          raise Ecto.MigrationError, message: "could not migrate, got: #{inspect error}"
        :already_up ->
          version
        :ok ->
          version
      end
    end
  end

  defp raise_no_migration_in_file(file) do
    raise Ecto.MigrationError, message: "file #{Path.relative_to_cwd(file)} does not contain any Ecto.Migration"
  end
end