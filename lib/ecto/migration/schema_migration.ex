defmodule Ecto.Migration.SchemaMigration do
  # Define a schema that works with the schema_migrations table
  @moduledoc false
  use Ecto.Model

  alias Ecto.Migration.Config

  @primary_key Config.primary_key()
  schema "schema_migrations" do
    timestamps updated_at: false
  end

  @table %Ecto.Migration.Table{name: :schema_migrations}
  @opts [timeout: :infinity, log: false]

  def ensure_schema_migrations_table!(repo) do
    adapter = repo.adapter

    # DDL queries do not log, so we do not need
    # to pass log: false here.
    unless adapter.ddl_exists?(repo, @table, @opts) do
      column_name = Config.primary_key_column(:name)
      column_type = Config.primary_key_column(:type)

      adapter.execute_ddl(repo,
        {:create, @table, [
          {:add, column_name, column_type, primary_key: true},
          {:add, :inserted_at, :datetime, []}]}, @opts)
    end

    :ok
  end

  def migrated_versions(repo) do
    repo.all from(p in __MODULE__, select: p.version), @opts
  end

  def up(repo, version) do
    repo.insert %__MODULE__{version: version}, @opts
  end

  def down(repo, version) do
    repo.delete %__MODULE__{version: version}, @opts
  end
end
