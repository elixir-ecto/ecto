defmodule Ecto.TestAdapter do
  @behaviour Ecto.Adapter

  alias Ecto.Migration.SchemaMigration

  defmacro __before_compile__(_opts), do: :ok
  def start_link(_repo, _opts), do: :ok
  def id_types(_repo), do: %{binary_id: Ecto.UUID}

  ## Queryable

  def all(_repo, %{from: {_, SchemaMigration}}, _, _),
    do: Enum.map(migrated_versions(), &List.wrap/1)
  def all(_repo, _query, _params, _opts),
    do: [[1]]

  def update_all(_repo, _query, _params, _opts), do: {1, nil}

  def delete_all(_repo, %{from: {_, SchemaMigration}}, [version], _) do
    Process.put(:migrated_versions, List.delete(migrated_versions(), version))
    {1, nil}
  end
  def delete_all(_repo, _query, _params, _opts), do: {1, nil}

  ## Model

  def insert(_repo, {"schema_migrations", _}, val, _, _, _) do
    version = Keyword.fetch!(val, :version)
    Process.put(:migrated_versions, [version|migrated_versions()])
    {:ok, [version: 1]}
  end

  def insert(repo, source, fields, {key, :id, nil}, return, opts),
    do: insert(repo, source, fields, nil, [key|return], opts)
  def insert(_repo, _source, _fields, _autogen, return, _opts),
    do: {:ok, Enum.zip(return, 1..length(return))}

  # Notice the list of changes is never empty.
  def update(_repo, _source, [_|_], _filters, _autogen, return, _opts),
    do: {:ok, Enum.zip(return, 1..length(return))}

  def delete(_repo, _source, _filter, _autogen, _opts),
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

Application.put_env(:ecto, Ecto.TestRepo, [])

defmodule Ecto.TestRepo do
  use Ecto.Repo, otp_app: :ecto, adapter: Ecto.TestAdapter
end
