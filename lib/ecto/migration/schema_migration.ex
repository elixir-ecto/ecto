defmodule Ecto.Migration.SchemaMigration do
  # Define a schema that works with the schema_migrations table
  @moduledoc false
  use Ecto.Schema

  import Ecto.Query, only: [from: 2]

  @primary_key false
  schema "schema_migrations" do
    field :version, :integer
    timestamps updated_at: false
  end

  @opts [timeout: :infinity, log: false]

  def ensure_schema_migrations_table!(repo, prefix) do
    adapter = repo.__adapter__
    create_migrations_table(adapter, repo, prefix)
  end

  def migrated_versions(repo, prefix) do
    repo.all from(p in __MODULE__, select: p.version) |> Map.put(:prefix, prefix), @opts
  end

  def up(repo, version, prefix) do
    repo.insert! %__MODULE__{version: version} |> Ecto.put_meta(prefix: prefix), @opts
  end

  def down(repo, version, prefix) do
    repo.delete_all from(p in __MODULE__, where: p.version == ^version) |> Map.put(:prefix, prefix), @opts
  end

  defp create_migrations_table(adapter, repo, prefix) do
    table = %Ecto.Migration.Table{name: :schema_migrations, prefix: prefix}

    # DDL queries do not log, so we do not need to pass log: false here.
    adapter.execute_ddl(repo,
      {:create_if_not_exists, table, [
        {:add, :version, :bigint, primary_key: true},
        {:add, :inserted_at, :datetime, []}]}, @opts)
  end
end
