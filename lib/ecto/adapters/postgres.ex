defmodule Ecto.Adapters.Postgres do
  @moduledoc false

  # This module handles the connections to the Postgres database with poolboy.
  # Each repository has their own pool.

  @behaviour Ecto.Adapter
  @default_port 5432

  alias Ecto.Adapters.Postgres.SQL
  alias Ecto.Query.Query
  alias Ecto.Query.Util

  defmacro __using__(_opts) do
    quote do
      def __postgres__(:pool_name) do
        __MODULE__.Pool
      end
    end
  end

  @doc false
  def start(repo) do
    { pool_opts, worker_opts } = prepare_start(repo)
    :poolboy.start(pool_opts, worker_opts)
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
    sql = SQL.select(query)
    result = transaction(repo, sql)

    case result do
      { { :select, _ }, rows } ->
        { return_type, _ } = query.select.expr
        binding = query.select.binding
        entities = Util.collect_entities(query)
        vars = Util.merge_to_vars(binding, entities)
        { :ok, Enum.map(rows, &transform_row(&1, return_type, vars)) }
      { :error, _ } = err -> err
    end
  end

  def create(repo, entity) do
    sql = SQL.insert(entity)
    result = transaction(repo, sql)

    case result do
      { { :insert, _, _ }, [{ primary_key }] } ->
        { :ok, primary_key }
      { { :insert, _, _ }, _ } ->
        { :ok, nil }
      { :error, _ } = err -> err
    end
  end

  def update(repo, entity) do
    sql = SQL.update(entity)
    result = transaction(repo, sql)

    case result do
      { { :update, _ }, _ } -> :ok
      { :error, _ } = err -> err
    end
  end

  def update_all(repo, query, binds, values) do
    sql = SQL.update_all(query, binds, values)
    result = transaction(repo, sql)

    case result do
      { { :update, nrows }, _ } -> { :ok, nrows }
      { :error, _ } = err -> err
    end
  end

  def delete(repo, entity) do
    sql = SQL.delete(entity)
    result = transaction(repo, sql)

    case result do
      { { :delete, _ }, _ } -> :ok
      { :error, _ } = err -> err
    end
  end

  def delete_all(repo, query) do
    sql = SQL.delete_all(query)
    result = transaction(repo, sql)

    case result do
      { { :delete, nrows }, _ } -> { :ok, nrows }
      { :error, _ } = err -> err
    end
  end

  # Only use internally for now in tests
  # Only works reliably with pool_size = 1

  @doc false
  def transaction_begin(repo) do
    result = transaction(repo, "BEGIN")
    case result do
      { :begin, _ } -> :ok
      { :error, _ } = err -> err
    end
  end

  @doc false
  def transaction_rollback(repo) do
    result = transaction(repo, "ROLLBACK")
    case result do
      { :rollback, _ } -> :ok
      { :error, _ } = err -> err
    end
  end

  @doc false
  def transaction_commit(repo) do
    result = transaction(repo, "COMMIT")
    case result do
      { :commit, _ } -> :ok
      { :error, _ } = err -> err
    end
  end

  @doc false
  def query(repo, sql), do: transaction(repo, sql)

  @doc false
  def transaction(repo, sql) when is_binary(sql) do
    :poolboy.transaction(repo.__postgres__(:pool_name), fn(conn) ->
      :pgsql_connection.simple_query(sql, { :pgsql_connection, conn })
    end)
  end

  @doc false
  def transaction(repo, fun) when is_function(fun, 1) do
    :poolboy.transaction(repo.__postgres__(:pool_name), fun)
  end

  defp fix_worker_opts(opts) do
    Enum.map(opts, fn
      { :username, v } -> { :user, v }
      { :hostname, v } -> { :host, binary_to_list(v) }
      rest -> rest
    end)
  end

  defp transform_row(row, return_type, vars) do
    case return_type do
      :single -> elem(row, 0)
      :list -> tuple_to_list(row)
      :tuple -> row
      { :entity, var } ->
        entity = Keyword.fetch!(vars, var)
        row = tuple_to_list(row)
        list_to_tuple([entity|row])
    end
  end

  defp prepare_start(repo) do
    # Use :application.ensure_started for R16B01
    case :application.start(:pgsql) do
      :ok -> :ok
      { :error, { :already_started, _ } } -> :ok
      { :error, reason } ->
        raise "could not start :pgsql application, reason: #{inspect reason}"
    end

    pool_name = repo.__postgres__(:pool_name)
    opts      = Ecto.Repo.parse_url(repo.url, @default_port)

    { pool_opts, worker_opts } = Dict.split(opts, [:size, :max_overflow])
    pool_opts = pool_opts
      |> Keyword.update(:size, 5, &binary_to_integer(&1))
      |> Keyword.update(:max_overflow, 10, &binary_to_integer(&1))

    pool_opts = pool_opts ++ [
      name: { :local, pool_name },
      worker_module: :pgsql_connection ]
    worker_opts = fix_worker_opts(worker_opts)

    { pool_opts, worker_opts }
  end
end
