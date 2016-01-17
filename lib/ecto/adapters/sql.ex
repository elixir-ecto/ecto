defmodule Ecto.Adapters.SQL do
  @moduledoc """
  Behaviour and implementation for SQL adapters.

  The implementation for SQL adapter relies on `DBConnection`
  to provide pooling, prepare, execute and more.

  Developers that use `Ecto.Adapters.SQL` should implement
  the callbacks required both by this module and the ones
  from `Ecto.Adapters.SQL.Query` about building queries.
  """

  @doc false
  defmacro __using__(adapter) do
    quote do
      @behaviour Ecto.Adapter
      @behaviour Ecto.Adapter.Migration
      @behaviour Ecto.Adapter.Transaction

      @conn __MODULE__.Connection
      @adapter unquote(adapter)

      ## Worker

      @doc false
      defmacro __before_compile__(env) do
        Ecto.Adapters.SQL.__before_compile__(@conn, env)
      end

      @doc false
      def start_link(repo, opts) do
        {:ok, _} = Application.ensure_all_started(@adapter)
        Ecto.Adapters.SQL.start_link(@conn, @adapter, repo, opts)
      end

      ## Types

      @doc false
      def autogenerate(:id), do: nil
      def autogenerate(:embed_id), do: Ecto.UUID.autogenerate()
      def autogenerate(:binary_id), do: Ecto.UUID.autogenerate()

      @doc false
      def loaders({:embed, _} = type, _), do: [&Ecto.Adapters.SQL.load_embed(type, &1)]
      def loaders(:binary_id, type), do: [Ecto.UUID, type]
      def loaders(_, type), do: [type]

      @doc false
      def dumpers({:embed, _} = type, _), do: [&Ecto.Adapters.SQL.dump_embed(type, &1)]
      def dumpers(:binary_id, type), do: [type, Ecto.UUID]
      def dumpers(_, type), do: [type]

      ## Query

      @doc false
      def prepare(:all, query),        do: {:cache, @conn.all(query)}
      def prepare(:update_all, query), do: {:cache, @conn.update_all(query)}
      def prepare(:delete_all, query), do: {:cache, @conn.delete_all(query)}

      @doc false
      def prepare_execute(repo, meta, prepared, params, preprocess, opts) do
        Ecto.Adapters.SQL.prepare_execute(repo, meta, prepared, params, preprocess, opts)
      end

      @doc false
      def execute(repo, meta, prepared, params, preprocess, opts) do
        Ecto.Adapters.SQL.execute(repo, meta, prepared, params, preprocess, opts)
      end

      @doc false
      def insert_all(repo, %{source: {prefix, source}}, header, rows, returning, opts) do
        Ecto.Adapters.SQL.insert_all(repo, @conn, prefix, source, header, rows, returning, opts)
      end

      @doc false
      def insert(repo, %{source: {prefix, source}}, params, returning, opts) do
        {fields, values} = :lists.unzip(params)
        sql = @conn.insert(prefix, source, fields, [fields], returning)
        Ecto.Adapters.SQL.struct(repo, @conn, sql, values, returning, opts)
      end

      @doc false
      def update(repo, %{source: {prefix, source}}, fields, filter, returning, opts) do
        {fields, values1} = :lists.unzip(fields)
        {filter, values2} = :lists.unzip(filter)
        sql = @conn.update(prefix, source, fields, filter, returning)
        Ecto.Adapters.SQL.struct(repo, @conn, sql, values1 ++ values2, returning, opts)
      end

      @doc false
      def delete(repo, %{source: {prefix, source}}, filter, opts) do
        {filter, values} = :lists.unzip(filter)
        sql = @conn.delete(prefix, source, filter, [])
        Ecto.Adapters.SQL.struct(repo, @conn, sql, values, [], opts)
      end

      ## Transaction

      @doc false
      def transaction(repo, opts, fun) do
        Ecto.Adapters.SQL.transaction(repo, opts, fun)
      end

      @doc false
      def rollback(repo, value) do
        Ecto.Adapters.SQL.rollback(repo, value)
      end

      ## Migration

      @doc false
      def execute_ddl(repo, definition, opts) do
        sqls = @conn.execute_ddl(definition)

        for sql <- List.wrap(sqls) do
          Ecto.Adapters.SQL.query!(repo, sql, [], opts)
        end

        :ok
      end

      defoverridable [prepare: 2, execute: 6, insert: 5, update: 6, delete: 4, insert_all: 6,
                      execute_ddl: 3, loaders: 2, dumpers: 2, autogenerate: 1]
    end
  end

  @doc """
  Converts the given query to SQL according to its kind and the
  adapter in the given repository.

  ## Examples

  The examples below are meant for reference. Each adapter will
  return a different result:

      Ecto.Adapters.SQL.to_sql(:all, repo, Post)
      {"SELECT p.id, p.title, p.inserted_at, p.created_at FROM posts as p", []}

      Ecto.Adapters.SQL.to_sql(:update_all, repo,
                              from(p in Post, update: [set: [title: ^"hello"]]))
      {"UPDATE posts AS p SET title = $1", ["hello"]}

  """
  @spec to_sql(:all | :update_all | :delete_all, Ecto.Repo.t, Ecto.Queryable.t) ::
               {String.t, [term]}
  def to_sql(kind, repo, queryable) do
    adapter = repo.__adapter__

    plan =
      Ecto.Queryable.to_query(queryable)
      |> Ecto.Query.Planner.query(kind, repo, adapter)
    case plan do
      {:execute, _meta, %{statement: statement}, params} ->
        {statement, params}
      {:execute, _meta, prepared, params} ->
        {prepared, params}
      {:prepare_execute, _meta, prepared, params, _} ->
        {prepared, params}
    end
  end

  @doc """
  Same as `query/4` but raises on invalid queries.
  """
  @spec query!(Ecto.Repo.t, String.t, [term], Keyword.t) ::
               %{rows: nil | [tuple], num_rows: non_neg_integer} | no_return
  def query!(repo, sql, params, opts \\ []) do
    query!(repo, sql, params, fn x -> x end, opts)
  end

  defp query!(repo, sql, params, mapper, opts) do
    case query(repo, sql, params, mapper, opts) do
      {:ok, result} -> result
      {:error, err} -> raise err
    end
  end

  @doc """
  Runs custom SQL query on given repo.

  In case of success, it must return an `:ok` tuple containing
  a map with at least two keys:

    * `:num_rows` - the number of rows affected

    * `:rows` - the result set as a list. `nil` may be returned
      instead of the list if the command does not yield any row
      as result (but still yields the number of affected rows,
      like a `delete` command without returning would)

  ## Options

    * `:timeout` - The time in milliseconds to wait for a query to finish,
      `:infinity` will wait indefinitely. (default: 15_000)
    * `:pool_timeout` - The time in milliseconds to wait for a call to the pool
      to finish, `:infinity` will wait indefinitely. (default: 5_000)

    * `:log` - When false, does not log the query

  ## Examples

      iex> Ecto.Adapters.SQL.query(MyRepo, "SELECT $1::integer + $2", [40, 2])
      {:ok, %{rows: [{42}], num_rows: 1}}

  """
  @spec query(Ecto.Repo.t, String.t, [term], Keyword.t) ::
              {:ok, %{rows: nil | [tuple], num_rows: non_neg_integer}} | {:error, Exception.t}
  def query(repo, sql, params, opts \\ []) do
    query(repo, sql, params, fn x -> x end, opts)
  end

  defp query(repo, sql, params, mapper, opts) do
    sql_call(repo, :query, sql, params, mapper, opts)
  end

  defp sql_call(repo, callback, sql, params, mapper, opts) do
    {pool, default_opts} = repo.__pool__
    conn = get_conn(pool) || pool
    opts = [decode_mapper: mapper] ++ with_log(repo, params, opts ++ default_opts)
    apply(repo.__sql__, callback, [conn, sql, params, opts])
  end

  ## Worker

  @pool_timeout 5_000
  @timeout 15_000

  @doc false
  def __before_compile__(conn, env) do
    config = Module.get_attribute(env.module, :config)
    pool   = Keyword.get(config, :pool, DBConnection.Poolboy)
    name   = Keyword.get(config, :pool_name, default_pool_name(env.module, config))

    config =
      config
      |> Keyword.delete(:name)
      |> Keyword.put(:pool, normalize_pool(pool))
      |> Keyword.put_new(:timeout, @timeout)
      |> Keyword.put_new(:pool_timeout, @pool_timeout)

    quote do
      @doc false
      def __sql__, do: unquote(conn)

      @doc false
      def __pool__, do: {unquote(name), unquote(Macro.escape(config))}
    end
  end

  defp normalize_pool(Ecto.Adapters.SQL.Sandbox),
    do: DBConnection.Ownership
  defp normalize_pool(pool),
    do: pool

  defp default_pool_name(repo, config) do
    Module.concat(Keyword.get(config, :name, repo), Pool)
  end

  @doc false
  def start_link(connection, adapter, repo, opts) do
    unless Code.ensure_loaded?(connection) do
      raise """
      could not find #{inspect connection}.

      Please verify you have added #{inspect adapter} as a dependency:

          {#{inspect adapter}, ">= 0.0.0"}

      And remember to recompile Ecto afterwards by cleaning the current build:

          mix deps.clean ecto
      """
    end

    {pool_name, pool_opts} = repo.__pool__
    opts = [name: pool_name] ++ Keyword.delete(opts, :pool) ++ pool_opts
    {mod, opts} = connection.connection(opts)

    if function_exported?(repo, :after_connect, 1) and not Keyword.has_key?(opts, :after_connect) do
      IO.puts :stderr, "warning: #{inspect repo}.after_connect/1 is deprecated. If you want to " <>
                       "perform some action after connecting, please set after_connect: {module, fun, args}" <>
                       "in your repository configuration"
      opts = Keyword.put(opts, :after_connect, {repo, :after_connect, []})
    end

    DBConnection.start_link(mod, opts)
  end

  ## Types

  @doc false
  def load_embed(type, value) do
    Ecto.Type.load(type, value, fn
      {:embed, _} = type, value -> load_embed(type, value)
      type, value -> Ecto.Type.cast(type, value)
    end)
  end

  @doc false
  def dump_embed(type, value) do
    Ecto.Type.dump(type, value, fn
      {:embed, _} = type, value -> dump_embed(type, value)
      _type, value -> {:ok, value}
    end)
  end

  ## Query

  @doc false
  def insert_all(repo, conn, prefix, source, header, rows, returning, opts) do
    {rows, params} = unzip_inserts(header, rows)
    sql = conn.insert(prefix, source, header, rows, returning)
    %{rows: rows, num_rows: num} = query!(repo, sql, Enum.reverse(params), nil, opts)
    {num, rows}
  end

  defp unzip_inserts(header, rows) do
    Enum.map_reduce rows, [], fn fields, params ->
      Enum.map_reduce header, params, fn key, acc ->
        case :lists.keyfind(key, 1, fields) do
          {^key, value} -> {key, [value|acc]}
          false -> {nil, acc}
        end
      end
    end
  end

  @doc false
  def prepare_execute(repo, _meta, prepared, params, nil, opts) do
    {query, result} = sql_call!(repo, :prepare_execute, prepared, params, nil, opts)
    %{rows: rows, num_rows: num} = result
    {query, {num, rows}}
  end

  def prepare_execute(repo, %{select: %{fields: fields}}, prepared, params, preprocess, opts) do
    mapper = &process_row(&1, preprocess, fields)
    {query, result} = sql_call!(repo, :prepare_execute, prepared, params, mapper, opts)
    %{rows: rows, num_rows: num} = result
    {query, {num, rows}}
  end

  @doc false
  def execute(repo, _meta, %{} = prepared, params, nil, opts) do
    %{rows: rows, num_rows: num} = sql_call!(repo, :execute, prepared, params, nil, opts)
    {num, rows}
  end

  def execute(repo, %{select: %{fields: fields}}, %{} = prepared, params, preprocess, opts) do
    mapper = &process_row(&1, preprocess, fields)
    %{rows: rows, num_rows: num} = sql_call!(repo, :execute, prepared, params, mapper, opts)
    {num, rows}
  end

  def execute(repo, _meta, prepared, params, nil, opts) do
    %{rows: rows, num_rows: num} = sql_call!(repo, :query, prepared, params, nil, opts)
    {num, rows}
  end

  def execute(repo, %{select: %{fields: fields}}, prepared, params, preprocess, opts) do
    mapper = &process_row(&1, preprocess, fields)
    %{rows: rows, num_rows: num} = sql_call!(repo, :query, prepared, params, mapper, opts)
    {num, rows}
  end

  defp sql_call!(repo, callback, sql, params, mapper, opts) do
    case sql_call(repo, callback, sql, params, mapper, opts) do
      {:ok, res}        -> res
      {:ok, query, res} -> {query, res}
      {:error, err}     -> raise err
    end
  end

  @doc false
  def struct(repo, conn, sql, values, returning, opts) do
    case query(repo, sql, values, fn x -> x end, opts) do
      {:ok, %{rows: nil, num_rows: 1}} ->
        {:ok, []}
      {:ok, %{rows: [values], num_rows: 1}} ->
        {:ok, Enum.zip(returning, values)}
      {:ok, %{num_rows: 0}} ->
        {:error, :stale}
      {:error, err} ->
        case conn.to_constraints(err) do
          []          -> raise err
          constraints -> {:invalid, constraints}
        end
    end
  end

  defp process_row(row, preprocess, fields) do
    Enum.map_reduce(fields, row, fn
      {:&, _, [_, fields]} = field, acc ->
        case split_and_not_nil(acc, length(fields), true, []) do
          {nil, rest} -> {nil, rest}
          {val, rest} -> {preprocess.(field, val, nil), rest}
        end
      field, [h|t] ->
        {preprocess.(field, h, nil), t}
    end) |> elem(0)
  end

  defp split_and_not_nil(rest, 0, true, _acc), do: {nil, rest}
  defp split_and_not_nil(rest, 0, false, acc), do: {:lists.reverse(acc), rest}

  defp split_and_not_nil([nil|t], count, all_nil?, acc) do
    split_and_not_nil(t, count - 1, all_nil?, [nil|acc])
  end

  defp split_and_not_nil([h|t], count, _all_nil?, acc) do
    split_and_not_nil(t, count - 1, false, [h|acc])
  end

  ## Transactions

  @doc false
  def transaction(repo, opts, fun) do
   {pool, default_opts} = repo.__pool__
    opts = with_log(repo, [], opts ++ default_opts)
    case get_conn(pool) do
      nil  -> do_transaction(pool, opts, fun)
      conn -> DBConnection.transaction(conn, fn(_) -> fun.() end, opts)
    end
  end

  defp do_transaction(pool, opts, fun) do
    run = fn(conn) ->
      try do
        put_conn(pool, conn)
        fun.()
      after
        delete_conn(pool)
      end
    end
    DBConnection.transaction(pool, run, opts)
  end

  @doc false
  def rollback(repo, value) do
    {pool, _} = repo.__pool__
    case get_conn(pool) do
      nil  -> raise "cannot call rollback outside of transaction"
      conn -> DBConnection.rollback(conn, value)
    end
  end

  ## Log

  defp with_log(repo, params, opts) do
    case Keyword.pop(opts, :log, true) do
      {true, opts}  -> [log: &log(repo, params, &1)] ++ opts
      {false, opts} -> opts
    end
  end

  defp log(repo, params, entry) do
    %{connection_time: query_time, decode_time: decode_time,
      pool_time: queue_time, result: result, query: query} = entry
    repo.log(%Ecto.LogEntry{query_time: query_time, decode_time: decode_time, queue_time: queue_time,
                            result: result, params: params, query: String.Chars.to_string(query)})
  end

  ## Connection helpers

  defp put_conn(pool, conn) do
    _ = Process.put(key(pool), conn)
    :ok
  end

  defp get_conn(pool) do
    Process.get(key(pool))
  end

  defp delete_conn(pool) do
    _ = Process.delete(key(pool))
    :ok
  end

  defp key(pool), do: {__MODULE__, pool}
end
