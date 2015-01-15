defmodule Ecto.Migration.SchemaMigration do
  # Define a schema that works with the schema_migrations table
  @moduledoc false

  import Ecto.Query, only: [from: 2]
  use Ecto.Schema

  @primary_key {:version, :integer, []}
  schema "schema_migrations" do
  end

  @table %Ecto.Migration.Table{name: :schema_migrations, primary_key: false}

  def ensure_schema_migrations_table!(repo) do
    adapter = repo.adapter

    unless adapter.ddl_exists?(repo, @table) do
      adapter.execute_ddl(repo,
        {:create, @table, [{:add, :version, :bigint, primary_key: true}]})
    end

    :ok
  end

  def migrated_versions(repo) do
    repo.all from p in __MODULE__, select: p.version
  end

  def up(repo, version) do
    repo.insert %__MODULE__{version: version}
  end

  def down(repo, version) do
    repo.delete %__MODULE__{version: version}
  end
end