defmodule Ecto.Adapters.Postgres do
  @moduledoc false

  @behaviour Ecto.Adapter
  @default_port 5432

  alias Ecto.Adapters.Postgres.SQL
  alias Ecto.Query.Query
  alias Ecto.Query.BuilderUtil

  defmacro __using__(_opts) do
    quote do
      def __postgres__(:pool_name) do
        __MODULE__.Pool
      end
    end
  end

  def start_link(repo) do
    case :application.ensure_started(:pgsql) do
      :ok -> :ok
      { :error, reason } ->
        raise "could not start :pgsql application, reason: #{inspect reason}"
    end

    pool_name = repo.__postgres__(:pool_name)
    opts      = Ecto.Repo.parse_url(repo.url, @default_port)

    { pool_opts, worker_opts } = Dict.split(opts, [:size, :max_overflow])
    pool_opts = pool_opts ++ [
      name: { :local, pool_name },
      worker_module: :pgsql_connection ]
    worker_opts = fix_worker_opts(worker_opts)

    :poolboy.start_link(pool_opts, worker_opts)
  end

  def fetch(repo, Query[] = query) do
    sql = SQL.select(query)
    result = transaction(repo, fn(conn) ->
      :pgsql_connection.simple_query(sql, { :pgsql_connection, conn })
    end)

    case result do
      { :error, _ } = err -> err
      { { :select, _nrows }, rows } ->
        { return_type, _ } = query.select.expr
        binding = query.select.binding
        vars = BuilderUtil.merge_binding_vars(binding, query.froms)
        Enum.map(rows, transform_row(&1, return_type, vars))
    end
  end

  def create(repo, entity) do
    sql = SQL.insert(entity)
    result = transaction(repo, fn(conn) ->
      :pgsql_connection.simple_query(sql, { :pgsql_connection, conn })
    end)

    case result do
      { { :insert, _, _ }, _rows } -> :ok
      { :error, _ } = err -> err
    end
  end

  defp transaction(repo, fun) do
    :poolboy.transaction(repo.__postgres__(:pool_name), fun)
  end

  defp fix_worker_opts(opts) do
    Enum.map(opts, fn
      { :username, v } -> { :user, v }
      { :hostname, v } -> { :host, binary_to_list(v) }
      rest -> rest
    end)
  end

  # TODO: Convert :null -> nil
  # TODO: Test this !!!
  defp transform_row(row, return_type, vars) do
    case return_type do
      :single -> elem(row, 0)
      :list -> tuple_to_list(row)
      :tuple -> row
      { :entity, var } ->
        { _, entity } = Dict.fetch!(vars, var)
        row = tuple_to_list(row)
        list_to_tuple([entity|row])
    end
  end
end
