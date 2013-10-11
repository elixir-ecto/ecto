defmodule Ecto.Migrator do
  @moduledoc """
  This module provides the migration API.

  ## Example

      defmodule MyApp.MigrationExample do
        def up do
          "CREATE TABLE user(id serial PRIMARY_KEY, username varchar(25));"
        end

        def down do
          "DROP TABLE user;"
        end
      end

      Ecto.Migrator.up(Repo, 20080906120000, MyApp.MigrationExample)
  """

  @doc "Runs an up migration on the given repository"
  def up(repo, version, module) do
    repo.adapter.migrate_up(repo, version, module.up)
  end

  @doc "Runs a down migration on the given repository"
  def down(repo, version, module) do
    repo.adapter.migrate_down(repo, version, module.down)
  end

  defp get_all_migration_versions(files) do
    Enum.map(files, fn(file) ->
      [v | _] = String.split(Path.basename(file), "_")
      binary_to_integer(v)
    end)
  end

  defp ensure_no_duplication(versions_list, repo) do
    case has_duplications(versions_list) do
      false ->
        case repo.adapter.migrated_versions(repo) do
          {:error, err} -> {:error, err}
          [] -> versions_list
          versions ->
            Enum.filter(versions_list, fn(migration_version) ->
              not {migration_version} in versions
            end)
        end
      {true, version } ->
        raise Ecto.MigrationError, message: 
        """
        Current migration can't be executed.
      
        Versions are duplicated: #{version}
        """
    end
  end

  def run_up(repo, directory) do
    all_files = :filelib.fold_files(directory, ".", true, fn(f, acc) -> [f | acc] end, [])
    all_migrations_files = Enum.filter(all_files, fn(file) -> Regex.match?(%r"\d+_.+\.exs", file) end)
    pending_migrations = all_migrations_files |> get_all_migration_versions |> ensure_no_duplication(repo)
    Enum.filter(pending_migrations, fn(migration_version) -> 
      case execute_migration(repo, migration_version, all_migrations_files) do
        {:success, _, _} -> true
        _ -> false
      end
    end)
  end

  defp execute_migration(repo, migration_version, migration_files) do
    [migration_file_path] = Enum.filter(migration_files, fn(file) ->
      [v | _] = String.split(Path.basename(file), "_")
      binary_to_integer(v) == migration_version
    end)
    [{migration_module, _}] = Code.load_file(migration_file_path)
    case function_exported?(migration_module, :__migration__, 0) do
      true ->
        case repo.adapter.migrate_up(repo, migration_version, migration_module.up) do
          {:error, err} -> 
            {:error, err}
          :already_up ->
            {:error, :already_up}
          :ok ->
            {:success, migration_version, migration_file_path}
        end
      false ->
        raise Ecto.MigrationError, message: 
        """
        Module #{migration_module} must export __migration__/0 from Ecto.Migration.
        """
    end
  end

  defp has_duplications([]) do
    false
  end

  defp has_duplications([h | t]) do
    case h in t do 
      true -> {true, h};
      false -> has_duplications(t)
    end
  end
end