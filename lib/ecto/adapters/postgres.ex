defmodule Ecto.Adapters.Postgres do
  @moduledoc false

  # TODO: Make this module public and document the adapter options
  # This module handles the connections to the Postgres database with poolboy.
  # Each repository has their own pool.

  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Migrations

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

  def start_link(repo) do
    { pool_opts, worker_opts } = prepare_start(repo)
    :poolboy.start_link(pool_opts, worker_opts)
  end

  def stop(repo) do
    pool_name = repo.__postgres__(:pool_name)
    :poolboy.stop(pool_name)
  end

  def all(repo, Query[] = query) do
    result = query(repo, SQL.select(query))

    case result do
      { :ok, Postgrex.Result[rows: rows] } ->
        # Transform each row based on select expression
        transformed = Enum.map(rows, fn row ->
          values = tuple_to_list(row)
          QueryExpr[expr: expr] = Normalizer.normalize_select(query.select)
          transform_row(expr, values, query.models) |> elem(0)
        end)

        # Combine records in case of assoc selector
        expr = query.select.expr
        if Ecto.Associations.assoc_select?(expr) do
          transformed = Ecto.Associations.transform_result(expr, transformed, query)
        end

        { :ok, transformed }
      { :error, _ } = err -> err
    end
  end

  def create(repo, entity) do
    result = query(repo, SQL.insert(entity))

    case result do
      { :ok, Postgrex.Result[rows: [{ primary_key }]] } ->
        { :ok, primary_key }
      { :ok, _ }->
        { :ok, nil }
      err -> err
    end
  end

  def update(repo, entity) do
    case query(repo, SQL.update(entity)) do
      { :ok, Postgrex.Result[num_rows: nrows] } -> { :ok, nrows }
      err -> err
    end
  end

  def update_all(repo, query, values) do
    case query(repo, SQL.update_all(query, values)) do
      { :ok, Postgrex.Result[num_rows: nrows] } -> { :ok, nrows }
      err -> err
    end
  end

  def delete(repo, entity) do
    case query(repo, SQL.delete(entity)) do
      { :ok, Postgrex.Result[num_rows: nrows] } -> { :ok, nrows }
      err -> err
    end
  end

  def delete_all(repo, query) do
    case query(repo, SQL.delete_all(query)) do
      { :ok, Postgrex.Result[num_rows: nrows] } -> { :ok, nrows }
      err -> err
    end
  end

  # We expose the querying function because we need it in tests.
  @doc false
  def query(repo, sql) when is_binary(sql) do
    :poolboy.transaction(repo.__postgres__(:pool_name), fn conn ->
      Postgrex.Connection.query(conn, sql)
    end)
  end

  def query(repo, fun) when is_function(fun, 1) do
    :poolboy.transaction(repo.__postgres__(:pool_name), fun)
  end

  defp transform_row({ :{}, _, list }, values, models) do
    { result, values } = transform_row(list, values, models)
    { list_to_tuple(result), values }
  end

  defp transform_row({ _, _ } = tuple, values, models) do
    { result, values } = transform_row(tuple_to_list(tuple), values, models)
    { list_to_tuple(result), values }
  end

  defp transform_row(list, values, models) when is_list(list) do
    { result, values } = Enum.reduce(list, { [], values }, fn elem, { res, values } ->
      { result, values } = transform_row(elem, values, models)
      { [result|res], values }
    end)

    { Enum.reverse(result), values }
  end

  defp transform_row({ :&, _, [_] } = var, values, models) do
    model = Util.find_model(models, var)
    entity = model.__model__(:entity)
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

  defp prepare_start(repo) do
    pool_name = repo.__postgres__(:pool_name)
    opts      = Ecto.Repo.parse_url(repo.url, @default_port)

    { pool_opts, worker_opts } = Dict.split(opts, [:size, :max_overflow])
    pool_opts = pool_opts
      |> Keyword.update(:size, 5, &binary_to_integer(&1))
      |> Keyword.update(:max_overflow, 10, &binary_to_integer(&1))

    pool_opts = pool_opts ++ [
      name: { :local, pool_name },
      worker_module: Postgrex.Connection ]

    worker_opts = worker_opts ++ [decoder: &decoder/5]

    { pool_opts, worker_opts }
  end

  defp decoder(_type, :bytea, _oid, default, param) do
    value = default.(param)
    Ecto.Binary[value: value]
  end

  defp decoder(_type, :interval, _oid, default, param) do
    { mon, day, sec } = default.(param)
    Ecto.Interval[month: mon, day: day, sec: sec]
  end

  defp decoder(_type, timestamp, _oid, default, param) when timestamp in [:timestamp, :timestamptz] do
    { { year, mon, day }, { hour, min, sec } } = default.(param)
    Ecto.DateTime[year: year, month: mon, day: day, hour: hour, min: min, sec: sec]
  end

  defp decoder(_type, _sender, _oid, default, param) do
    default.(param)
  end

  ## Transaction API

  # Only use internally for now in tests
  # Only works reliably with pool_size = 1

  @doc false
  def transaction_begin(repo) do
    case query(repo, "BEGIN") do
      { :ok, _ } -> :ok
      err -> err
    end
  end

  @doc false
  def transaction_rollback(repo) do
    case query(repo, "ROLLBACK") do
      { :ok, _ } -> :ok
      err -> err
    end
  end

  @doc false
  def transaction_commit(repo) do
    case query(repo, "COMMIT") do
      { :ok, _ } -> :ok
      err -> err
    end
  end

  ## Migration API

  def migrate_up(repo, version, commands) do
    case check_migration_version(repo, version) do
      { :ok, Postgrex.Result[num_rows: 0] } ->
        # TODO: We need to wrap this inside a database transaction
        case query(repo, commands) do
          { :ok, _ } ->
            case insert_migration_version(repo, version) do
              { :ok, _ } -> :ok
              err -> err
            end
          err ->
            err
        end
      { :ok, _ } ->
        :already_up
      err ->
        err
    end
  end

  def migrate_down(repo, version, commands) do
    case check_migration_version(repo, version) do
      { :ok, Postgrex.Result[num_rows: 0] } ->
        :missing_up
      { :ok, _ } ->
        # TODO: We need to wrap this inside a database transaction
        case query(repo, commands) do
          { :ok, _ } ->
            case delete_migration_version(repo, version) do
              { :ok, _ } -> :ok
              err -> err
            end
          err ->
            err
        end
      err ->
        err
    end
  end

  def migrated_versions(repo) do
    case create_migrations_table(repo) do
      { :ok, _ } ->
        case query(repo, "SELECT version FROM schema_migrations;") do
          { :ok, Postgrex.Result[rows: rows] } ->
            { :ok, Enum.map(rows, &elem(&1, 0)) }
          err ->
            err
        end
      err ->
        err
    end
  end

  defp create_migrations_table(repo) do
    query(repo, "CREATE TABLE IF NOT EXISTS schema_migrations (id serial primary key, version decimal)")
  end

  defp check_migration_version(repo, version) do
    case create_migrations_table(repo) do
      { :ok, _ } -> query(repo, "SELECT version FROM schema_migrations WHERE version = #{version}")
      err -> err
    end
  end

  defp insert_migration_version(repo, version) do
    query(repo, "INSERT INTO schema_migrations(version) VALUES (#{version})")
  end

  defp delete_migration_version(repo, version) do
    query(repo, "DELETE FROM schema_migrations WHERE version = #{version}")
  end
end
