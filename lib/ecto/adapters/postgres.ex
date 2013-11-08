defmodule Ecto.Adapters.Postgres do
  @moduledoc false

  # TODO: Make this module public and document the adapter options
  # This module handles the connections to the Postgres database with poolboy.
  # Each repository has their own pool.

  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Migrations
  @behaviour Ecto.Adapter.Transactions
  @behaviour Ecto.Adapter.TestTransactions

  @default_port 5432

  alias Ecto.Adapters.Postgres.SQL
  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util
  alias Ecto.Query.Normalizer

  ## Adapter API

  defmacro __using__(_opts) do
    quote do
      def __postgres__(:pool_name) do
        __MODULE__.Pool
      end
    end
  end

  def start_link(repo, opts) do
    { pool_opts, worker_opts } = prepare_start(repo, opts)
    :poolboy.start_link(pool_opts, worker_opts)
  end

  def stop(repo) do
    pool_name = repo.__postgres__(:pool_name)
    :poolboy.stop(pool_name)
  end

  def all(repo, Query[] = query) do
    Postgrex.Result[rows: rows] = query(repo, SQL.select(query))

    # Transform each row based on select expression
    transformed = Enum.map(rows, fn row ->
      values = tuple_to_list(row)
      QueryExpr[expr: expr] = Normalizer.normalize_select(query.select)
      transform_row(expr, values, query.sources) |> elem(0)
    end)

    # Combine records in case of assoc selector
    expr = query.select.expr
    if Ecto.Associations.assoc_select?(expr) do
      transformed = Ecto.Associations.transform_result(expr, transformed, query)
    end
    transformed
  end

  def create(repo, entity) do
    case query(repo, SQL.insert(entity)) do
      Postgrex.Result[rows: [{ primary_key }]] ->
        primary_key
      _ ->
        nil
    end
  end

  def update(repo, entity) do
    Postgrex.Result[num_rows: nrows] = query(repo, SQL.update(entity))
    nrows
  end

  def update_all(repo, query, values) do
    Postgrex.Result[num_rows: nrows] = query(repo, SQL.update_all(query, values))
    nrows
  end

  def delete(repo, entity) do
    Postgrex.Result[num_rows: nrows] = query(repo, SQL.delete(entity))
    nrows
  end

  def delete_all(repo, query) do
    Postgrex.Result[num_rows: nrows] = query(repo, SQL.delete_all(query))
    nrows
  end

  def query(repo, sql) do
    use_worker(repo, fn worker ->
      Postgrex.Connection.query!(worker, sql)
    end)
  end

  defp transform_row({ :{}, _, list }, values, sources) do
    { result, values } = transform_row(list, values, sources)
    { list_to_tuple(result), values }
  end

  defp transform_row({ _, _ } = tuple, values, sources) do
    { result, values } = transform_row(tuple_to_list(tuple), values, sources)
    { list_to_tuple(result), values }
  end

  defp transform_row(list, values, sources) when is_list(list) do
    { result, values } = Enum.reduce(list, { [], values }, fn elem, { res, values } ->
      { result, values } = transform_row(elem, values, sources)
      { [result|res], values }
    end)

    { Enum.reverse(result), values }
  end

  defp transform_row({ :&, _, [_] } = var, values, sources) do
    entity = Util.find_source(sources, var) |> Util.entity
    entity_size = length(entity.__entity__(:field_names))
    { entity_values, values } = Enum.split(values, entity_size)

    if Enum.all?(entity_values, &(nil?(&1))) do
      { nil, values }
    else
      { entity.__entity__(:allocate, entity_values), values }
    end
  end

  defp transform_row(_, values, _entities) do
    [value|values] = values
    { value, values }
  end

  defp prepare_start(repo, opts) do
    pool_name = repo.__postgres__(:pool_name)
    { pool_opts, worker_opts } = Dict.split(opts, [:size, :max_overflow])

    pool_opts = pool_opts
                |> Keyword.update(:size, 5, &binary_to_integer(&1))
                |> Keyword.update(:max_overflow, 10, &binary_to_integer(&1))

    pool_opts = [ name: { :local, pool_name },
                  worker_module: Postgrex.Connection ] ++ pool_opts

    worker_opts = worker_opts
                  |> Keyword.put(:decoder, &decoder/6)
                  |> Keyword.put_new(:port, @default_port)

    { pool_opts, worker_opts }
  end

  defp decoder(:bytea, _type, _oid, :binary, default, param) do
    value = default.(param)
    Ecto.Binary[value: value]
  end

  defp decoder(:interval, _type, _oid, :binary, default, param) do
    { mon, day, sec } = default.(param)
    Ecto.Interval[month: mon, day: day, sec: sec]
  end

  defp decoder(timestamp, _type, _oid, :binary, default, param) when timestamp in [:timestamp, :timestamptz] do
    { { year, mon, day }, { hour, min, sec } } = default.(param)
    Ecto.DateTime[year: year, month: mon, day: day, hour: hour, min: min, sec: sec]
  end

  defp decoder(_type, _sender, _oid, _format, default, param) do
    default.(param)
  end

  ## Transaction API

  def transaction(repo, fun) do
    worker = checkout_worker(repo)
    try do
      Postgrex.Connection.begin!(worker)
      value = fun.()
      Postgrex.Connection.commit!(worker)
      { :ok, value }
    catch
      :throw, :ecto_rollback ->
        Postgrex.Connection.rollback!(worker)
        :error
      type, term ->
        Postgrex.Connection.rollback!(worker)
        :erlang.raise(type, term, System.stacktrace)
    after
      checkin_worker(repo)
    end
  end

  defp use_worker(repo, fun) do
    pool = repo.__postgres__(:pool_name)
    key = { :ecto_transaction_pid, pool }

    if value = Process.get(key) do
      in_transaction = true
      worker = elem(value, 0)
    else
      worker = :poolboy.checkout(pool)
    end

    try do
      fun.(worker)
    after
      if !in_transaction do
        :poolboy.checkin(pool, worker)
      end
    end
  end

  defp checkout_worker(repo) do
    pool = repo.__postgres__(:pool_name)
    key = { :ecto_transaction_pid, pool }

    case Process.get(key) do
      { worker, counter } ->
        Process.put(key, { worker, counter + 1 })
        worker
      nil ->
        worker = :poolboy.checkout(pool)
        Process.put(key, { worker, 1 })
        worker
    end
  end

  defp checkin_worker(repo) do
    pool = repo.__postgres__(:pool_name)
    key = { :ecto_transaction_pid, pool }

    case Process.get(key) do
      { worker, 1 } ->
        :poolboy.checkin(pool, worker)
        Process.delete(key)
      { worker, counter } ->
        Process.put(key, { worker, counter - 1 })
    end
    :ok
  end

  ## Test transaction API

  def begin_test_transaction(repo) do
    pool = repo.__postgres__(:pool_name)
    :poolboy.transaction(pool, fn worker ->
      Postgrex.Connection.begin!(worker)
    end)
  end

  def rollback_test_transaction(repo) do
    pool = repo.__postgres__(:pool_name)
    :poolboy.transaction(pool, fn worker ->
      Postgrex.Connection.rollback!(worker)
    end)
  end

  ## Migration API

  def migrate_up(repo, version, commands) do
    case check_migration_version(repo, version) do
      Postgrex.Result[num_rows: 0] ->
        run_commands(repo, commands, fn ->
          insert_migration_version(repo, version)
        end)
      _ ->
        :already_up
    end
  end

  def migrate_down(repo, version, commands) do
    case check_migration_version(repo, version) do
      Postgrex.Result[num_rows: 0] ->
        :missing_up
      _ ->
        run_commands(repo, commands, fn ->
          delete_migration_version(repo, version)
        end)
    end
  end

  defp run_commands(repo, commands, fun) do
    transaction(repo, fn ->
      Enum.each(commands, fn command ->
        query(repo, command)
        fun.()
      end)
    end)
    :ok
  end

  def migrated_versions(repo) do
    create_migrations_table(repo)
    Postgrex.Result[rows: rows] = query(repo, "SELECT version FROM schema_migrations")
    Enum.map(rows, &elem(&1, 0))
  end

  defp create_migrations_table(repo) do
    query(repo, "CREATE TABLE IF NOT EXISTS schema_migrations (id serial primary key, version decimal)")
  end

  defp check_migration_version(repo, version) do
    create_migrations_table(repo)
    query(repo, "SELECT version FROM schema_migrations WHERE version = #{version}")
  end

  defp insert_migration_version(repo, version) do
    query(repo, "INSERT INTO schema_migrations(version) VALUES (#{version})")
  end

  defp delete_migration_version(repo, version) do
    query(repo, "DELETE FROM schema_migrations WHERE version = #{version}")
  end
end
