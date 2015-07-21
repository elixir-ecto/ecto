defmodule Ecto.Migration.SchemaMigration do
  # Define a schema that works with the schema_migrations table
  @moduledoc false
  use Ecto.Model

  @primary_key false
  schema "schema_migrations" do
    field :version, :integer
    timestamps updated_at: false
  end

  @table %Ecto.Migration.Table{name: :schema_migrations}
  @opts [timeout: :infinity, log: false]

  def ensure_schema_migrations_table!(repo) do
    adapter = repo.__adapter__
    create_migrations_table(adapter, repo)
  end

  def migrated_versions(repo) do
    repo.all from(p in __MODULE__, select: p.version), @opts
  end

  def up(repo, version) do
    repo.insert! %__MODULE__{version: version}, @opts
  end

  def down(repo, version) do
    repo.delete_all from(p in __MODULE__, where: p.version == ^version), @opts
  end

  defp create_migrations_table(Ecto.Adapters.MySQL = adapter, repo) do
    unless table_exists?(repo) do
      do_create_migrations_table(:create, adapter, repo)
    end
    :ok
  end

  defp create_migrations_table(adapter, repo) do
    do_create_migrations_table(:create_if_not_exists, adapter, repo)
  end

  defp do_create_migrations_table(command, adapter, repo) do
    # DDL queries do not log, so we do not need
    # to pass log: false here.
    adapter.execute_ddl(repo,
      {command, @table, [
        {:add, :version, :bigint, primary_key: true},
        {:add, :inserted_at, :datetime, []}]}, @opts)
  end

  defp table_exists?(repo) do
    sql =
      """
      SELECT COUNT(1)
        FROM information_schema.tables
      WHERE table_schema = SCHEMA()
            AND table_name = '#{escape_string(to_string(@table.name))}'
      """
    %{rows: [[count]]} = Ecto.Adapters.SQL.query(repo, sql, [])
    count > 0
  end

  defp escape_string(value) when is_binary(value) do
    value
    |> :binary.replace("'", "''", [:global])
    |> :binary.replace("\\", "\\\\", [:global])
  end
end
