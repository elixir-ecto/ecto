defmodule Ecto.Adapters.Postgres do
  @moduledoc false

  # TODO: Make this module public and document the adapter options
  # This module handles the connections to the Postgres database with poolboy.
  # Each repository has their own pool.

  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Migrations
  @behaviour Ecto.Adapter.Storage
  @behaviour Ecto.Adapter.Transactions
  @behaviour Ecto.Adapter.TestTransactions

  @default_port 5432

  alias Ecto.Adapters.Postgres.SQL
  alias Ecto.Adapters.Postgres.Worker
  alias Ecto.Associations.Assoc
  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util
  alias Postgrex.TypeInfo

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
    pg_query = query.select |> normalize_select |> query.select

    Postgrex.Result[rows: rows] = query(repo, SQL.select(pg_query))

    # Transform each row based on select expression
    transformed = Enum.map(rows, fn row ->
      values = tuple_to_list(row)
      QueryExpr[expr: expr] = normalize_select(pg_query.select)
      transform_row(expr, values, pg_query.sources) |> elem(0)
    end)

    transformed
      |> Ecto.Associations.Assoc.run(query)
      |> preload(repo, query)
  end

  def create(repo, entity) do
    module      = elem(entity, 0)
    primary_key = module.__entity__(:primary_key)
    pk_value    = entity.primary_key

    returning = module.__entity__(:entity_kw, entity)
      |> Enum.filter(fn { _, val } -> val == nil end)
      |> Keyword.keys

    if primary_key && !pk_value do
      returning = [primary_key] ++ returning
    end

    case query(repo, SQL.insert(entity, returning)) do
      Postgrex.Result[rows: [values]] ->
        #Setup the entity to use the RETURNING values
        Enum.zip(returning, tuple_to_list(values)) |> entity.update
      _ ->
        entity
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
      Worker.query!(worker, sql)
    end)
  end

  defp prepare_start(repo, opts) do
    pool_name = repo.__postgres__(:pool_name)
    { pool_opts, worker_opts } = Dict.split(opts, [:size, :max_overflow])

    pool_opts = pool_opts
      |> Keyword.update(:size, 5, &binary_to_integer(&1))
      |> Keyword.update(:max_overflow, 10, &binary_to_integer(&1))

    pool_opts = [
      name: { :local, pool_name },
      worker_module: Worker ] ++ pool_opts

    worker_opts = worker_opts
      |> Keyword.put(:decoder, &decoder/4)
      |> Keyword.put_new(:port, @default_port)

    { pool_opts, worker_opts }
  end

  def normalize_select(QueryExpr[expr: { :assoc, _, [_, _] } = assoc] = expr) do
    normalize_assoc(assoc) |> expr.expr
  end

  def normalize_select(QueryExpr[expr: _] = expr), do: expr

  defp normalize_assoc({ :assoc, _, [_, _] } = assoc) do
    { var, fields } = Assoc.decompose_assoc(assoc)
    normalize_assoc(var, fields)
  end

  defp normalize_assoc(var, fields) do
    nested = Enum.map(fields, fn { _field, nested } ->
      { var, fields } = Assoc.decompose_assoc(nested)
      normalize_assoc(var, fields)
    end)
    { var, nested }
  end

  ## Result set transformation

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

  defp preload(results, repo, Query[] = query) do
    pos = Util.locate_var(query.select.expr, { :&, [], [0] })
    fields = Enum.map(query.preloads, &(&1.expr)) |> Enum.concat
    Ecto.Associations.Preloader.run(results, repo, fields, pos)
  end

  ## Postgrex casting

  defp decoder(TypeInfo[sender: "interval"], :binary, default, param) do
    { mon, day, sec } = default.(param)
    Ecto.Interval[month: mon, day: day, sec: sec]
  end

  defp decoder(TypeInfo[sender: sender], :binary, default, param) when sender in ["timestamp", "timestamptz"] do
    { { year, mon, day }, { hour, min, sec } } = default.(param)
    Ecto.DateTime[year: year, month: mon, day: day, hour: hour, min: min, sec: sec]
  end

  defp decoder(_type, _format, default, param) do
    default.(param)
  end

  ## Transaction API

  def transaction(repo, fun) do
    worker = checkout_worker(repo)
    try do
      Worker.begin!(worker)
      value = fun.()
      Worker.commit!(worker)
      { :ok, value }
    catch
      :throw, :ecto_rollback ->
        Worker.rollback!(worker)
        :error
      type, term ->
        Worker.rollback!(worker)
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
      Worker.begin!(worker)
    end)
  end

  def rollback_test_transaction(repo) do
    pool = repo.__postgres__(:pool_name)
    :poolboy.transaction(pool, fn worker ->
      Worker.rollback!(worker)
    end)
  end

  ## Storage API

  def storage_up(opts) do

    #TODO: allow the user to specify those options either in the Repo or on command line
    database_options = %s(ENCODING='UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8')

    creation_cmd = ""

    if password = opts[:password] do
      creation_cmd = %s(PGPASSWORD=#{ password } )
    end

    creation_cmd =
      creation_cmd <>
      %s(psql -U #{ opts[:username] } ) <>
      %s(--host #{ opts[:hostname] } ) <>
      %s(-c "CREATE DATABASE #{ opts[:database] } ) <>
      %s(#{database_options};" )

    output = System.cmd creation_cmd

    cond do
      output =~ %r/already exists/ -> { :error, :already_up }
      output =~ %r/(ERROR|FATAL|psql):/ -> { :error, output }
      true -> :ok
    end
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
