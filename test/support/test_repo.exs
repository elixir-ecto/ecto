defmodule Ecto.TestAdapter do
  @behaviour Ecto.Adapter

  alias Ecto.Migration.SchemaMigration

  defmacro __before_compile__(_opts), do: :ok

  def start_link(_repo, opts) do
    Ecto.TestRepo.Pool = opts[:name]
    Ecto.TestRepo.Pool = opts[:pool]
    Ecto.TestRepo      = opts[:repo]

    :ecto   = opts[:otp_app]
    "user"  = opts[:username]
    "pass"  = opts[:password]
    "hello" = opts[:database]
    "local" = opts[:hostname]

    Task.start_link(fn -> :timer.sleep(:infinity) end)
  end

  ## Types

  def loaders(:binary_id, type), do: [Ecto.UUID, type]
  def loaders(_primitive, type), do: [type]

  def dumpers(:binary_id, type), do: [type, Ecto.UUID]
  def dumpers(_primitive, type), do: [type]

  def autogenerate(:id), do: nil
  def autogenerate(:embed_id), do: Ecto.UUID.autogenerate
  def autogenerate(:binary_id), do: Ecto.UUID.autogenerate

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

  def execute(_repo, _meta, {op, %{from: {source, _}}}, _params, _preprocess, _opts) do
    send self, {op, source}
    {1, nil}
  end

  ## Schema

  def insert_all(_repo, %{source: {_, source}}, _header, rows, _returning, _opts) do
    send self(), {:insert_all, source, rows}
    {1, nil}
  end

  def insert(_repo, %{source: {nil, "schema_migrations"}}, val, _, _) do
    version = Keyword.fetch!(val, :version)
    Process.put(:migrated_versions, [version|migrated_versions()])
    {:ok, [version: 1]}
  end

  def insert(_repo, %{context: nil}, _fields, return, _opts),
    do: send(self, :insert) && {:ok, Enum.zip(return, 1..length(return))}
  def insert(_repo, %{context: {:invalid, _}=res}, _fields, _return, _opts),
    do: res

  # Notice the list of changes is never empty.
  def update(_repo, %{context: nil}, [_|_], _filters, return, _opts),
    do: send(self, :update) && {:ok, Enum.zip(return, 1..length(return))}
  def update(_repo, %{context: {:invalid, _}=res}, [_|_], _filters, _return, _opts),
    do: res

  def delete(_repo, _model_meta, _filter, _opts),
    do: send(self, :delete) && {:ok, []}

  ## Transactions

  def transaction(_repo, _opts, fun) do
    # Makes transactions "trackable" in tests
    send self, {:transaction, fun}
    try do
      {:ok, fun.()}
    catch
      :throw, {:ecto_rollback, value} ->
        {:error, value}
    end
  end

  def rollback(_repo, value) do
    send self, {:rollback, value}
    throw {:ecto_rollback, value}
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

Application.put_env(:ecto, Ecto.TestRepo, [user: "invalid"])

defmodule Ecto.TestRepo do
  use Ecto.Repo, otp_app: :ecto, adapter: Ecto.TestAdapter
end

Ecto.TestRepo.start_link(url: "ecto://user:pass@local/hello")
