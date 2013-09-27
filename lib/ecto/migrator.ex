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
end
