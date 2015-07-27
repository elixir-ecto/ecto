defmodule Ecto.TestAdapter do
  @behaviour Ecto.Adapter

  alias Ecto.Migration.SchemaMigration

  defmacro __before_compile__(_opts), do: :ok

  def start_link(_repo, _opts) do
    Task.start_link(fn -> :timer.sleep(:infinity) end)
  end

  ## Types

  def load(:binary_id, data), do: Ecto.Type.load(Ecto.UUID, data, &load/2)
  def load(type, data), do: Ecto.Type.load(type, data, &load/2)

  def dump(:binary_id, data), do: Ecto.Type.dump(Ecto.UUID, data, &dump/2)
  def dump(type, data), do: Ecto.Type.dump(type, data, &dump/2)

  def embed_id(%Ecto.Embedded{}), do: Ecto.UUID.generate

  ## Queryable

  def prepare(operation, query), do: {:nocache, {operation, query}}

  def execute(_repo, _, {:all, %{from: {_, SchemaMigration}}}, _, _, _) do
    {length(migrated_versions()),
     Enum.map(migrated_versions(), &List.wrap/1)}
   end

  def execute(_repo, _, {:all, _}, _, _, _) do
    {1, [[1]]}
  end

  def execute(_repo, _meta, {:delete_all, %{from: {_, SchemaMigration}}}, [version], _, _) do
    Process.put(:migrated_versions, List.delete(migrated_versions(), version))
    {1, nil}
  end

  def execute(_repo, _meta, {_, _}, _params, _preprocess, _opts) do
    {1, nil}
  end

  ## Model

  def insert(_repo, {nil, "schema_migrations", _}, val, _, _, _) do
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

  defp migrated_versions do
    Process.get(:migrated_versions) || []
  end
end

Application.put_env(:ecto, Ecto.TestRepo, [])

defmodule Ecto.TestRepo do
  use Ecto.Repo, otp_app: :ecto, adapter: Ecto.TestAdapter
end

Ecto.TestRepo.start_link()
