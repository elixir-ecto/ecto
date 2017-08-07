defmodule Ecto.Adapters.SQL do
  @moduledoc """
  Behaviour and implementation for SQL adapters.

  The implementation for SQL adapter relies on `DBConnection`
  to provide pooling, prepare, execute and more.

  Developers that use `Ecto.Adapters.SQL` should implement
  the callbacks required both by this module and the ones
  from `Ecto.Adapters.SQL.Connection` for handling connections
  and performing queries.
  """

  @doc false
  defmacro __using__(adapter) do
    quote do
      @behaviour Ecto.Adapter
      @behaviour Ecto.Adapter.Migration
      @behaviour Ecto.Adapter.Transaction

      @conn __MODULE__.Connection
      @adapter unquote(adapter)

      @doc false
      defmacro __before_compile__(env) do
        Ecto.Adapters.SQL.__before_compile__(@conn, env)
      end

      @doc false
      def ensure_all_started(repo, type) do
        Ecto.Adapters.SQL.ensure_all_started(@adapter, repo, type)
      end

      @doc false
      def child_spec(repo, opts) do
        Ecto.Adapters.SQL.child_spec(@conn, @adapter, repo, opts)
      end

      ## Types

      @doc false
      def autogenerate(:id),        do: nil
      def autogenerate(:embed_id),  do: Ecto.UUID.generate()
      def autogenerate(:binary_id), do: Ecto.UUID.bingenerate()

      @doc false
      def loaders({:embed, _} = type, _), do: [&Ecto.Adapters.SQL.load_embed(type, &1)]
      def loaders(:binary_id, type),      do: [Ecto.UUID, type]
      def loaders(_, type),               do: [type]

      @doc false
      def dumpers({:embed, _} = type, _), do: [&Ecto.Adapters.SQL.dump_embed(type, &1)]
      def dumpers(:binary_id, type),      do: [type, Ecto.UUID]
      def dumpers(_, type),               do: [type]

      ## Query

      @doc false
      def prepare(:all, query),
        do: {:cache, {System.unique_integer([:positive]), IO.iodata_to_binary(@conn.all(query))}}
      def prepare(:update_all, query),
        do: {:cache, {System.unique_integer([:positive]), IO.iodata_to_binary(@conn.update_all(query))}}
      def prepare(:delete_all, query),
        do: {:cache, {System.unique_integer([:positive]), IO.iodata_to_binary(@conn.delete_all(query))}}

      @doc false
      def execute(repo, meta, query, params, process, opts) do
        Ecto.Adapters.SQL.execute(repo, meta, query, params, process, opts)
      end

      @doc false
      def stream(repo, meta, query, params, process, opts) do
        Ecto.Adapters.SQL.stream(repo, meta, query, params, process, opts)
      end

      @doc false
      def insert_all(repo, %{source: {prefix, source}}, header, rows,
                     {_, conflict_params, _} = on_conflict, returning, opts) do
        {rows, params} = Ecto.Adapters.SQL.unzip_inserts(header, rows)
        sql = @conn.insert(prefix, source, header, rows, on_conflict, returning)
        %{rows: rows, num_rows: num} =
          Ecto.Adapters.SQL.query!(repo, sql, Enum.reverse(params) ++ conflict_params, opts)
        {num, rows}
      end

      @doc false
      def insert(repo, %{source: {prefix, source}}, params,
                 {kind, conflict_params, _} = on_conflict, returning, opts) do
        {fields, values} = :lists.unzip(params)
        sql = @conn.insert(prefix, source, fields, [fields], on_conflict, returning)
        Ecto.Adapters.SQL.struct(repo, @conn, sql, {:insert, source, []}, values ++ conflict_params, kind, returning, opts)
      end

      @doc false
      def update(repo, %{source: {prefix, source}}, fields, params, returning, opts) do
        {fields, values1} = :lists.unzip(fields)
        {filter, values2} = :lists.unzip(params)
        sql = @conn.update(prefix, source, fields, filter, returning)
        Ecto.Adapters.SQL.struct(repo, @conn, sql, {:update, source, params}, values1 ++ values2, :raise, returning, opts)
      end

      @doc false
      def delete(repo, %{source: {prefix, source}}, params, opts) do
        {filter, values} = :lists.unzip(params)
        sql = @conn.delete(prefix, source, filter, [])
        Ecto.Adapters.SQL.struct(repo, @conn, sql, {:delete, source, params}, values, :raise, [], opts)
      end

      ## Transaction

      @doc false
      def transaction(repo, opts, fun) do
        Ecto.Adapters.SQL.transaction(repo, opts, fun)
      end

      @doc false
      def in_transaction?(repo) do
        Ecto.Adapters.SQL.in_transaction?(repo)
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

      defoverridable [prepare: 2, execute: 6, insert: 6, update: 6, delete: 4, insert_all: 7,
                      execute_ddl: 3, loaders: 2, dumpers: 2, autogenerate: 1, ensure_all_started: 2]
    end
  end

  @doc """
  Converts the given query to SQL according to its kind and the
  adapter in the given repository.

  ## Examples

  The examples below are meant for reference. Each adapter will
  return a different result:

      iex> Ecto.Adapters.SQL.to_sql(:all, repo, Post)
      {"SELECT p.id, p.title, p.inserted_at, p.created_at FROM posts as p", []}

      iex> Ecto.Adapters.SQL.to_sql(:update_all, repo,
                                    from(p in Post, update: [set: [title: ^"hello"]]))
      {"UPDATE posts AS p SET title = $1", ["hello"]}

  This function is also available under the repository with name `to_sql`:

      iex> Repo.to_sql(:all, Post)
      {"SELECT p.id, p.title, p.inserted_at, p.created_at FROM posts as p", []}

  """
  @spec to_sql(:all | :update_all | :delete_all, Ecto.Repo.t, Ecto.Queryable.t) ::
               {String.t, [term]}
  def to_sql(kind, repo, queryable) do
    adapter = repo.__adapter__

    queryable
    |> Ecto.Queryable.to_query()
    |> Ecto.Query.Planner.returning(kind == :all)
    |> Ecto.Query.Planner.query(kind, repo, adapter, 0)
    |> case do
      {_meta, {:cached, _reset, {_id, cached}}, params} ->
        {String.Chars.to_string(cached), params}
      {_meta, {:cache, _update, {_id, prepared}}, params} ->
        {prepared, params}
      {_meta, {:nocache, {_id, prepared}}, params} ->
        {prepared, params}
    end
  end

  @doc """
  Same as `query/4` but raises on invalid queries.
  """
  @spec query!(Ecto.Repo.t, String.t, [term], Keyword.t) ::
               %{:rows => nil | [[term] | binary],
                 :num_rows => non_neg_integer,
                 optional(atom) => any}
               | no_return
  def query!(repo, sql, params \\ [], opts \\ []) do
    query!(repo, sql, map_params(params), fn x -> x end, opts)
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
      {:ok, %{rows: [[42]], num_rows: 1}}

  For convenience, this function is also available under the repository:

      iex> MyRepo.query("SELECT $1::integer + $2", [40, 2])
      {:ok, %{rows: [[42]], num_rows: 1}}

  """
  @spec query(Ecto.Repo.t, String.t, [term], Keyword.t) ::
              {:ok, %{:rows => nil | [[term] | binary],
                      :num_rows => non_neg_integer,
                      optional(atom) => any}}
              | {:error, Exception.t}
  def query(repo, sql, params \\ [], opts \\ []) do
    query(repo, sql, map_params(params), fn x -> x end, opts)
  end

  defp query(repo, sql, params, mapper, opts) do
    sql_call(repo, :execute, [sql], params, mapper, opts)
  end

  defp sql_call(repo, callback, args, params, mapper, opts) do
    {repo_mod, pool, default_opts} = lookup_pool(repo)
    conn = get_conn(pool) || pool
    opts = [decode_mapper: mapper] ++ with_log(repo_mod, params, opts ++ default_opts)
    args = args ++ [params, opts]
    try do
      apply(repo_mod.__sql__, callback, [conn | args])
    rescue
      err in DBConnection.OwnershipError ->
        message = err.message <> "\nSee Ecto.Adapters.SQL.Sandbox docs for more information."
        reraise %{err | message: message}, System.stacktrace
    end
  end

  defp put_source(opts, %{sources: sources}) when tuple_size(elem(sources, 0)) == 2 do
    {source, _} = elem(sources, 0)
    Keyword.put(opts, :source, source)
  end
  defp put_source(opts, _) do
    opts
  end

  defp map_params(params) do
    Enum.map params, fn
      %{__struct__: _} = value ->
        {:ok, value} = Ecto.DataType.dump(value)
        value
      [_|_] = value ->
        {:ok, value} = Ecto.DataType.dump(value)
        value
      value ->
        value
    end
  end

  ## Worker

  @doc false
  def __before_compile__(conn, _env) do
    quote do
      @doc false
      def __sql__, do: unquote(conn)

      @doc """
      A convenience function for SQL-based repositories that executes the given query.

      See `Ecto.Adapters.SQL.query/3` for more information.
      """
      def query(sql, params \\ [], opts \\ []) do
        Ecto.Adapters.SQL.query(__MODULE__, sql, params, opts)
      end

      @doc """
      A convenience function for SQL-based repositories that executes the given query.

      See `Ecto.Adapters.SQL.query/3` for more information.
      """
      def query!(sql, params \\ [], opts \\ []) do
        Ecto.Adapters.SQL.query!(__MODULE__, sql, params, opts)
      end

      @doc """
      A convenience function for SQL-based repositories that translates the given query to SQL.

      See `Ecto.Adapters.SQL.query/3` for more information.
      """
      def to_sql(operation, queryable) do
        Ecto.Adapters.SQL.to_sql(operation, __MODULE__, queryable)
      end
    end
  end

  @doc false
  def ensure_all_started(adapter, repo, type) do
    opts = pool_config(repo, repo.config)
    with {:ok, from_pool} <- DBConnection.ensure_all_started(opts, type),
         {:ok, from_adapter} <- Application.ensure_all_started(adapter, type),
      # We always return the adapter to force it to be restarted if necessary
      do: {:ok, from_pool ++ List.delete(from_adapter, adapter) ++ [adapter]}
  end

  defp pool_config(repo, opts) do
    opts
    |> Keyword.drop([:loggers, :priv, :url])
    |> Keyword.put(:name, pool_name(repo, opts))
    |> Keyword.update(:pool, DBConnection.Poolboy, &normalize_pool/1)
  end

  defp normalize_pool(pool) do
    if Code.ensure_loaded?(pool) && function_exported?(pool, :unboxed_run, 2) do
      DBConnection.Ownership
    else
      pool
    end
  end

  defp pool_name(repo, config) do
    Keyword.get_lazy(config, :pool_name, fn ->
      Module.concat(Keyword.get(config, :name, repo), Pool)
    end)
  end

  @doc false
  def child_spec(connection, adapter, repo, opts) do
    unless Code.ensure_loaded?(connection) do
      raise """
      could not find #{inspect connection}.

      Please verify you have added #{inspect adapter} as a dependency:

          {#{inspect adapter}, ">= 0.0.0"}

      And remember to recompile Ecto afterwards by cleaning the current build:

          mix deps.clean --build ecto
      """
    end

    pool_config = pool_config(repo, opts)
    pool_name = Keyword.fetch!(pool_config, :name)
    Ecto.Registry.associate(self(), {repo, pool_name, pool_config})
    connection.child_spec(pool_config)
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
  def unzip_inserts(header, rows) do
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
  def execute(repo, meta, prepared, params, mapper, opts) do
    do_execute(repo, meta, prepared, params, mapper, put_source(opts, meta))
  end

  defp do_execute(repo, _meta, {:cache, update, {id, prepared}}, params, mapper, opts) do
    execute_and_cache(repo, id, update, prepared, params, mapper, opts)
  end

  defp do_execute(repo, _meta, {:cached, reset, {id, cached}}, params, mapper, opts) do
    execute_or_reset(repo, id, reset, cached, params, mapper, opts)
  end

  defp do_execute(repo, _meta, {:nocache, {_id, prepared}}, params, mapper, opts) do
    %{rows: rows, num_rows: num} =
      sql_call!(repo, :execute, [prepared], params, mapper, opts)
    {num, rows}
  end

  defp execute_and_cache(repo, id, update, prepared, params, mapper, opts) do
    name = "ecto_" <> Integer.to_string(id)
    case sql_call(repo, :prepare_execute, [name, prepared], params, mapper, opts) do
      {:ok, query, %{num_rows: num, rows: rows}} ->
        update.({id, query})
        {num, rows}
      {:error, err} ->
        raise err
    end
  end

  defp execute_or_reset(repo, id, reset, cached, params, mapper, opts) do
    case sql_call(repo, :execute, [cached], params, mapper, opts) do
      {:ok, %{num_rows: num, rows: rows}} ->
        {num, rows}
      {:error, err} ->
        raise err
      {:reset, err} ->
        reset.({id, String.Chars.to_string(cached)})
        raise err
    end
  end

  defp sql_call!(repo, callback, args, params, mapper, opts) do
    case sql_call(repo, callback, args, params, mapper, opts) do
      {:ok, res}    -> res
      {:error, err} -> raise err
    end
  end

  @doc """
  Returns a stream that runs a custom SQL query on given repo when reduced.

  In case of success it is a enumerable containing maps with at least two keys:

    * `:num_rows` - the number of rows affected

    * `:rows` - the result set as a list. `nil` may be returned
      instead of the list if the command does not yield any row
      as result (but still yields the number of affected rows,
      like a `delete` command without returning would)

  In case of failure it raises an exception.

  If the adapter supports a collectable stream, the stream may also be used as
  the collectable in `Enum.into/3`. Behaviour depends on the adapter.

  ## Options

    * `:timeout` - The time in milliseconds to wait for a query to finish,
      `:infinity` will wait indefinitely (default: 15_000)
    * `:pool_timeout` - The time in milliseconds to wait for a call to the pool
      to finish, `:infinity` will wait indefinitely (default: 5_000)
    * `:log` - When false, does not log the query
    * `:max_rows` - The number of rows to load from the database as we stream

  ## Examples

      iex> Ecto.Adapters.SQL.stream(MyRepo, "SELECT $1::integer + $2", [40, 2]) |> Enum.to_list()
      [%{rows: [[42]], num_rows: 1}]

  """
  @spec stream(Ecto.Repo.t, String.t, [term], Keyword.t) :: Enum.t
  def stream(repo, sql, params \\ [], opts \\ []) do
    Ecto.Adapters.SQL.Stream.__build__(repo, sql, params, fn x -> x end, opts)
  end

  @doc false
  def stream(repo, meta, prepared, params, mapper, opts) do
    do_stream(repo, meta, prepared, params, mapper, put_source(opts, meta))
  end

  def do_stream(repo, _meta, {:cache, _, {_, prepared}}, params, mapper, opts) do
    prepare_stream(repo, prepared, params, mapper, opts)
  end

  def do_stream(repo, _, {:cached, _, {_, cached}}, params, mapper, opts) do
    prepare_stream(repo, String.Chars.to_string(cached), params, mapper, opts)
  end

  def do_stream(repo, _meta, {:nocache, {_id, prepared}}, params, mapper, opts) do
    prepare_stream(repo, prepared, params, mapper, opts)
  end

  defp prepare_stream(repo, prepared, params, mapper, opts) do
    repo
    |> Ecto.Adapters.SQL.Stream.__build__(prepared, params, mapper, opts)
    |> Stream.map(fn(%{num_rows: nrows, rows: rows}) -> {nrows, rows} end)
  end

  @doc false
  def reduce(repo, statement, params, mapper, opts, acc, fun) do
    {repo_mod, pool, default_opts} = lookup_pool(repo)
    opts = [decode_mapper: mapper] ++ with_log(repo, params, opts ++ default_opts)
    case get_conn(pool) do
      nil  ->
        raise "cannot reduce stream outside of transaction"
      conn ->
        apply(repo_mod.__sql__, :stream, [conn, statement, params, opts])
        |> Enumerable.reduce(acc, fun)
    end
  end

  @doc false
  def into(repo, statement, params, mapper, opts) do
    {repo_mod, pool, default_opts} = lookup_pool(repo)
    opts = [decode_mapper: mapper] ++ with_log(repo_mod, params, opts ++ default_opts)
    case get_conn(pool) do
      nil  ->
        raise "cannot collect into stream outside of transaction"
      conn ->
        apply(repo_mod.__sql__, :stream, [conn, statement, params, opts])
        |> Collectable.into()
    end
  end

  @doc false
  def struct(repo, conn, sql, {operation, source, params}, values, on_conflict, returning, opts) do
    case query(repo, sql, values, fn x -> x end, opts) do
      {:ok, %{rows: nil, num_rows: 1}} ->
        {:ok, []}
      {:ok, %{rows: [values], num_rows: 1}} ->
        {:ok, Enum.zip(returning, values)}
      {:ok, %{num_rows: 0}} ->
        if on_conflict == :nothing, do: {:ok, []}, else: {:error, :stale}
      {:ok, %{num_rows: num_rows}} when num_rows > 1 ->
        raise Ecto.MultiplePrimaryKeyError,
              source: source, params: params, count: num_rows, operation: operation
      {:error, err} ->
        case conn.to_constraints(err) do
          []          -> raise err
          constraints -> {:invalid, constraints}
        end
    end
  end

  ## Transactions

  @doc false
  def transaction(repo, opts, fun) do
    {repo_mod, pool, default_opts} = lookup_pool(repo)
    opts = with_log(repo_mod, [], opts ++ default_opts)
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
  def in_transaction?(repo) do
    {_repo_mod, pool, _default_opts} = lookup_pool(repo)
    !!get_conn(pool)
  end

  @doc false
  def rollback(repo, value) do
    {_repo_mod, pool, _default_opts} = lookup_pool(repo)
    case get_conn(pool) do
      nil  -> raise "cannot call rollback outside of transaction"
      conn -> DBConnection.rollback(conn, value)
    end
  end

  ## Log

  defp with_log(repo, params, opts) do
    case Keyword.pop(opts, :log, true) do
      {true, opts}  -> [log: &log(repo, params, &1, opts)] ++ opts
      {false, opts} -> opts
    end
  end

  defp log(repo, params, entry, opts) do
    %{connection_time: query_time, decode_time: decode_time,
      pool_time: queue_time, result: result, query: query} = entry
    source = Keyword.get(opts, :source)
    caller_pid = Keyword.get(opts, :caller, self())
    query_string = String.Chars.to_string(query)
    repo.__log__(%Ecto.LogEntry{query_time: query_time, decode_time: decode_time,
                                queue_time: queue_time, result: log_result(result),
                                params: params, query: query_string,
                                ansi_color: sql_color(query_string), source: source,
                                caller_pid: caller_pid})
  end

  defp log_result({:ok, _query, res}), do: {:ok, res}
  defp log_result(other), do: other

  ## Connection helpers

  defp lookup_pool(repo) do
    Ecto.Registry.lookup(repo)
  end

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

  defp sql_color("SELECT" <> _), do: :cyan
  defp sql_color("ROLLBACK" <> _), do: :red
  defp sql_color("LOCK" <> _), do: :white
  defp sql_color("INSERT" <> _), do: :green
  defp sql_color("UPDATE" <> _), do: :yellow
  defp sql_color("DELETE" <> _), do: :red
  defp sql_color("begin" <> _), do: :magenta
  defp sql_color("commit" <> _), do: :magenta
  defp sql_color(_), do: nil
end
