defmodule Ecto.MockAdapter do
  @behaviour Ecto.Adapter

  defmacro __before_compile__(_opts), do: :ok
  def start_link(_repo, _opts), do: :ok
  def stop(_repo), do: :ok

  ## Queryable

  def all(_repo, %{from: {_, Ecto.Migration.SchemaMigration}}, _, _),
    do: Enum.map(migrated_versions(), &List.wrap/1)
  def all(_repo, _query, _params, _opts),
    do: [[1]]

  def update_all(_repo, _query, _values, _params, _opts), do: 1
  def delete_all(_repo, _query, _params, _opts), do: 1

  ## Model

  def insert(_repo, "schema_migrations", val, _, _) do
    version = Keyword.fetch!(val, :version)
    Process.put(:migrated_versions, [version|migrated_versions()])
    {:ok, [version: 1]}
  end

  def insert(_repo, _source, _fields, [_], _opts),
    do: {:ok, [id: 1]}

  # Notice the list of changes is never empty.
  def update(_repo, _source, [_|_], _filters, [_], _opts),
    do: {:ok, [id: 1]}

  def delete(_repo, "schema_migrations", val, _) do
    version = Keyword.fetch!(val, :version)
    Process.put(:migrated_versions, List.delete(migrated_versions(), version))
    {:ok, []}
  end

  def delete(_repo, _source, _filter, _opts),
    do: {:ok, []}

  ## Transactions

  def transaction(_repo, _opts, fun) do
    # Makes transactions "trackable" in tests
    send self, {:transaction, fun}
    {:ok, fun.()}
  end

  ## Migrations

  def supports_ddl_transaction? do
    Process.get(:supports_ddl_transaction?) || false
  end

  def execute_ddl(_repo, command, _) do
    Process.put(:last_command, command)
    :ok
  end

  def ddl_exists?(_repo, object, _) do
    Process.put(:last_exists, object)
    Process.get(:ddl_exists, true)
  end

  defp migrated_versions do
    Process.get(:migrated_versions) || []
  end
end

Application.put_env(:ecto, Ecto.MockRepo, adapter: Ecto.MockAdapter)

defmodule Ecto.MockRepo do
  use Ecto.Repo, otp_app: :ecto
end
