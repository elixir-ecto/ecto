defmodule Ecto.Migration.SchemaMigration do
  @moduledoc """
  Defines a schema that works with the schema_migrations table.

  This module is the default model used for the schema migrations table.
  It may be overridden by setting `schema_migrations_model: CustomMigration`
  in the config for your Ecto Repo.
  """

  use Ecto.Model

  @behaviour Ecto.Migration
  @primary_key {:version, :integer, []}
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
      adapter.execute_ddl(repo,
        {:create, @table, [
          {:add, :version, :bigint, primary_key: true},
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
