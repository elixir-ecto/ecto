defmodule Ecto.TestAdapter do
  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Queryable
  @behaviour Ecto.Adapter.Schema
  @behaviour Ecto.Adapter.Transaction

  alias Ecto.Migration.SchemaMigration

  defmacro __before_compile__(_opts), do: :ok

  def ensure_all_started(_, _) do
    {:ok, []}
  end

  def init(opts) do
    :ecto   = opts[:otp_app]
    "user"  = opts[:username]
    "pass"  = opts[:password]
    "hello" = opts[:database]
    "local" = opts[:hostname]

    {:ok, Supervisor.Spec.worker(Task, [fn -> :timer.sleep(:infinity) end]), %{meta: :meta}}
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

  # Migration emulation

  def execute(_, _, {:nocache, {:all, %{from: %{source: {"schema_migrations", _}}}}}, _, _) do
    {length(migrated_versions()), Enum.map(migrated_versions(), &List.wrap/1)}
  end

  def execute(_, _meta, {:nocache, {:delete_all, %{from: %{source: {_, SchemaMigration}}}}}, [version], _) do
    Process.put(:migrated_versions, List.delete(migrated_versions(), version))
    {1, nil}
  end

  # Regular operations

  def execute(_, _, {:nocache, {:all, query}}, _, _) do
    send test_process(), {:all, query}
    Process.get(:test_repo_all_results) || results_for_all_query(query)
  end

  def execute(_, _meta, {:nocache, {op, query}}, _params, _opts) do
    send test_process(), {op, query}
    {1, nil}
  end

  def stream(_, _meta, {:nocache, {:all, query}}, _params, _opts) do
    Stream.map([:execute], fn :execute ->
      send test_process(), {:stream, query}
      results_for_all_query(query)
    end)
  end

  defp results_for_all_query(%{select: %{fields: [_ | _] = fields}}) do
    values = List.duplicate(nil, length(fields) - 1)
    {1, [[1 | values]]}
  end

  defp results_for_all_query(%{select: %{fields: []}}) do
    {1, [[]]}
  end

  ## Schema

  def insert_all(_, meta, _header, rows, _on_conflict, _returning, _opts) do
    %{source: source, prefix: prefix} = meta
    send test_process(), {:insert_all, {prefix, source}, rows}
    {1, nil}
  end

  def insert(_, %{source: "schema_migrations"}, val, _, _, _) do
    version = Keyword.fetch!(val, :version)
    Process.put(:migrated_versions, [version | migrated_versions()])
    {:ok, []}
  end

  def insert(_, %{context: nil} = meta, _fields, _on_conflict, return, _opts) do
    %{source: source, prefix: prefix} = meta
    send(test_process(), {:insert, {prefix, source}})
    {:ok, Enum.zip(return, 1..length(return))}
  end

  def insert(_, %{context: context}, _fields, _on_conflict, _return, _opts) do
    context
  end

  # Notice the list of changes is never empty.
  def update(_, %{context: nil} = schema_meta, [_ | _], _filters, return, _opts) do
    %{source: source, prefix: prefix} = schema_meta
    send(test_process(), {:update, {prefix, source}})
    {:ok, Enum.zip(return, 1..length(return))}
  end

  def update(_, %{context: context}, [_ | _], _filters, _return, _opts) do
    context
  end

  def delete(_, %{context: nil} = schema_meta, _filter, _opts) do
    %{source: source, prefix: prefix} = schema_meta
    send(test_process(), {:delete, {prefix, source}})
    {:ok, []}
  end

  def delete(_, %{context: context}, _filter, _opts) do
    context
  end

  ## Transactions

  def transaction(mod, _opts, fun) do
    # Makes transactions "trackable" in tests
    Process.put({mod, :in_transaction?}, true)
    send test_process(), {:transaction, fun}
    try do
      {:ok, fun.()}
    catch
      :throw, {:ecto_rollback, value} ->
        {:error, value}
    after
      Process.delete({mod, :in_transaction?})
    end
  end

  def in_transaction?(mod) do
    Process.get({mod, :in_transaction?}) || false
  end

  def rollback(_, value) do
    send test_process(), {:rollback, value}
    throw {:ecto_rollback, value}
  end

  ## Migrations

  def lock_for_migrations(_, query, _opts, fun) do
    send test_process(), {:lock_for_migrations, fun}
    fun.(query)
  end

  def execute_ddl(_, command, _) do
    Process.put(:last_command, command)
    {:ok, []}
  end

  defp migrated_versions do
    Process.get(:migrated_versions, [])
  end

  def supports_ddl_transaction? do
    get_config(:supports_ddl_transaction?, false)
  end

  defp test_process do
    get_config(:test_process, self())
  end

  defp get_config(name, default) do
    :ecto
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(name, default)
  end
end

Application.put_env(:ecto, Ecto.TestRepo, [user: "invalid"])

defmodule Ecto.TestRepo do
  use Ecto.Repo, otp_app: :ecto, adapter: Ecto.TestAdapter

  def init(type, opts) do
    opts = [url: "ecto://user:pass@local/hello"] ++ opts
    opts[:parent] && send(opts[:parent], {__MODULE__, type, opts})
    {:ok, opts}
  end
end

Ecto.TestRepo.start_link()
