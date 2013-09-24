defmodule Ecto.Migrator do
  @moduledoc """
  This module provides migrations API. Migrations module must implement `up/0`
  and `down/0`.

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

  def up(repo, version, module) do
    repo.adapter.migrate_up(repo, version, module.up)
  end

  def down(repo, version, module) do
    repo.adapter.migrate_down(repo, version, module.down)
  end

end