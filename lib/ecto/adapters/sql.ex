defmodule Ecto.Adapters.SQL do
  @moduledoc """
  Behaviour and implementation for SQL adapters.

  The implementation for SQL adapter provides a
  pooled based implementation of SQL and also expose
  a query function to developers.

  Developers that use `Ecto.Adapters.SQL` should implement
  a connection module with specifics on how to connect
  to the database and also how to translate the queries
  to SQL.

  See `Ecto.Adapters.Connection` for connection processes and
  `Ecto.Adapters.SQL.Query` for the query semantics.
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
      defmacro __before_compile__(_env) do
        :ok
      end

      @doc false
      def start_link(repo, opts) do
        {:ok, _} = Application.ensure_all_started(@adapter)
        Ecto.Adapters.SQL.start_link(@conn, @adapter, repo, opts)
      end

      ## Types

      def embed_id(_), do: Ecto.UUID.generate
      def load(type, value), do: Ecto.Adapters.SQL.load(type, value, &load/2)
      def dump(type, value), do: Ecto.Adapters.SQL.dump(type, value, &dump/2)

      ## Query

      @doc false
      def prepare(:all, query),        do: {:cache, @conn.all(query)}
      def prepare(:update_all, query), do: {:cache, @conn.update_all(query)}
      def prepare(:delete_all, query), do: {:cache, @conn.delete_all(query)}

      @doc false
      def execute(repo, meta, prepared, params, preprocess, opts) do
        Ecto.Adapters.SQL.execute(repo, meta, prepared, params, preprocess, opts)
      end

      @doc false
      # Nil ids are generated in the database.
      def insert(repo, model_meta, params, {key, :id, nil}, returning, opts) do
        insert(repo, model_meta, params, nil, [key|returning], opts)
      end

      # Nil binary_ids are generated in the adapter.
      def insert(repo, model_meta, params, {key, :binary_id, nil}, returning, opts) do
        {req, resp} = Ecto.Adapters.SQL.bingenerate(key)
        case insert(repo, model_meta, req ++ params, nil, returning, opts) do
          {:ok, values}         -> {:ok, resp ++ values}
          {:error, _} = err     -> err
          {:invalid, _} = err   -> err
        end
      end

      def insert(repo, %{source: {prefix, source}}, params, _autogenerate, returning, opts) do
        {fields, values} = :lists.unzip(params)
        sql = @conn.insert(prefix, source, fields, returning)
        Ecto.Adapters.SQL.model(repo, @conn, sql, values, returning, opts)
      end

      @doc false
      def update(repo, %{source: {prefix, source}}, fields, filter, _autogenerate, returning, opts) do
        {fields, values1} = :lists.unzip(fields)
        {filter, values2} = :lists.unzip(filter)
        sql = @conn.update(prefix, source, fields, filter, returning)
        Ecto.Adapters.SQL.model(repo, @conn, sql, values1 ++ values2, returning, opts)
      end

      @doc false
      def delete(repo, %{source: {prefix, source}}, filter, _autogenarate, opts) do
        {filter, values} = :lists.unzip(filter)
        sql = @conn.delete(prefix, source, filter, [])
        Ecto.Adapters.SQL.model(repo, @conn, sql, values, [], opts)
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

      defoverridable [prepare: 2, execute: 6,
                      insert: 6, update: 7, delete: 5,
                      execute_ddl: 3, embed_id: 1,
                      load: 2, dump: 2]
    end
  end

  alias Ecto.Pool
  alias Ecto.Adapters.SQL.Sandbox

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

    {_meta, prepared, params} =
      Ecto.Queryable.to_query(queryable)
      |> Ecto.Query.Planner.query(kind, repo, adapter)

    {prepared, params}
  end

  @doc """
  Same as `query/4` but raises on invalid queries.
  """
  @spec query!(Ecto.Repo.t, String.t, [term], Keyword.t) ::
               %{rows: nil | [tuple], num_rows: non_neg_integer} | no_return
  def query!(repo, sql, params, opts \\ []) do
    query!(repo, sql, params, nil, opts)
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

    * `:timeout` - The time in milliseconds to wait for the call to finish,
      `:infinity` will wait indefinitely (default: 5000)

    * `:log` - When false, does not log the query

  ## Examples

      iex> Ecto.Adapters.SQL.query(MyRepo, "SELECT $1::integer + $2", [40, 2])
      {:ok, %{rows: [{42}], num_rows: 1}}

  """
  @spec query(Ecto.Repo.t, String.t, [term], Keyword.t) ::
              {:ok, %{rows: nil | [tuple], num_rows: non_neg_integer}} | {:error, Exception.t}
  def query(repo, sql, params, opts \\ []) do
    query(repo, sql, params, nil, opts)
  end

  defp query(repo, sql, params, mapper, opts) do
    case query(repo, sql, params, nil, mapper, opts) do
      {result, entry} ->
        log(repo, entry)
        result
      :noconnect ->
        # :noconnect can never be the reason a call fails because
        # it is converted to {:nodedown, node}. This means the exit
        # reason can be easily identified.
        exit({:noconnect, {__MODULE__, :query, [repo, sql, params, opts]}})
    end
  end

  defp query(repo, sql, params, outer_queue_time, mapper, opts) do
    {pool_mod, pool, timeout} = repo.__pool__
    opts    = Keyword.put_new(opts, :timeout, timeout)
    timeout = Keyword.fetch!(opts, :timeout)
    log?    = Keyword.get(opts, :log, true)

    query_fun = fn({mod, conn}, inner_queue_time) ->
      query(mod, conn, inner_queue_time || outer_queue_time, sql, params, log?, opts)
    end

    case Pool.run(pool_mod, pool, timeout, query_fun) do
      {:ok, {result, entry}} ->
        decode(result, entry, mapper)
      {:error, :noconnect} ->
        :noconnect
      {:error, :noproc} ->
        raise ArgumentError, "repo #{inspect repo} is not started, " <>
                             "please ensure it is part of your supervision tree"
    end
  end

  defp query(mod, conn, _queue_time, sql, params, false, opts) do
    {mod.query(conn, sql, params, opts), nil}
  end
  defp query(mod, conn, queue_time, sql, params, true, opts) do
    {query_time, result} = :timer.tc(mod, :query, [conn, sql, params, opts])
    entry = %Ecto.LogEntry{query: sql, params: params, connection_pid: conn,
                           query_time: query_time, queue_time: queue_time}
    {result, entry}
  end

  defp decode(result, nil, nil) do
    {result, nil}
  end
  defp decode(result, nil, mapper) do
    {decode(result, mapper), nil}
  end
  defp decode(result, entry, nil) do
    {result, %{entry | result: result}}
  end
  defp decode(result, %{query_time: query_time} = entry, mapper) do
    {decode_time, decoded} = :timer.tc(fn -> decode(result, mapper) end)
    {decoded, %{entry | result: decoded, query_time: query_time + decode_time}}
  end

  defp decode({:ok, %{rows: rows} = res}, mapper) when is_list(rows) do
    {:ok, %{res | rows: Enum.map(rows, mapper)}}
  end
  defp decode(other, _mapper) do
    other
  end

  defp log(_repo, nil), do: :ok
  defp log(repo, entry), do: repo.log(entry)

  @doc ~S"""
  Starts a transaction for test.

  This function work by starting a transaction and storing the connection
  back in the pool with an open transaction. On every test, we restart
  the test transaction rolling back to the appropriate savepoint.


  **IMPORTANT:** Test transactions only work if the connection pool is
  `Ecto.Adapters.SQL.Sandbox`

  ## Example

  The first step is to configure your database to use the
  `Ecto.Adapters.SQL.Sandbox` pool. You set those options in your
  `config/config.exs`:

      config :my_app, Repo,
        pool: Ecto.Adapters.SQL.Sandbox

  Since you don't want those options in your production database, we
  typically recommend to create a `config/test.exs` and add the
  following to the bottom of your `config/config.exs` file:

      import_config "config/#{Mix.env}.exs"

  Now with the test database properly configured, you can write
  transactional tests:

      # At the end of your test_helper.exs
      # From now, all tests happen inside a transaction
      Ecto.Adapters.SQL.begin_test_transaction(TestRepo)

      defmodule PostTest do
        # Tests that use the shared repository cannot be async
        use ExUnit.Case

        setup do
          # Go back to a clean slate at the beginning of every test
          Ecto.Adapters.SQL.restart_test_transaction(TestRepo)
          :ok
        end

        test "create comment" do
          assert %Post{} = TestRepo.insert!(%Post{})
        end
      end

  In some cases, you may want to start the test transaction only
  for specific tests and then roll it back. You can do it as:

      defmodule PostTest do
        # Tests that use the shared repository cannot be async
        use ExUnit.Case

        setup_all do
          # Wrap this case in a transaction
          Ecto.Adapters.SQL.begin_test_transaction(TestRepo)

          # Roll it back once we are done
          on_exit fn ->
            Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
          end

          :ok
        end

        setup do
          # Go back to a clean slate at the beginning of every test
          Ecto.Adapters.SQL.restart_test_transaction(TestRepo)
          :ok
        end

        test "create comment" do
          assert %Post{} = TestRepo.insert!(%Post{})
        end
      end

  """
  @spec begin_test_transaction(Ecto.Repo.t, Keyword.t) :: :ok
  def begin_test_transaction(repo, opts \\ []) do
    test_transaction(:begin, repo, opts)
  end

  @doc """
  Restarts a test transaction, see `begin_test_transaction/2`.
  """
  @spec restart_test_transaction(Ecto.Repo.t, Keyword.t) :: :ok
  def restart_test_transaction(repo, opts \\ []) do
    test_transaction(:restart, repo, opts)
  end

  @spec rollback_test_transaction(Ecto.Repo.t, Keyword.t) :: :ok
  def rollback_test_transaction(repo, opts \\ []) do
    test_transaction(:rollback, repo, opts)
  end

  defp test_transaction(fun, repo, opts) do
    case repo.__pool__ do
      {Sandbox, pool, timeout} ->
        opts = Keyword.put_new(opts, :timeout, timeout)
        test_transaction(pool, fun, &repo.log/1, opts)
      {pool_mod, _, _} ->
        raise """
        cannot #{fun} test transaction with pool #{inspect pool_mod}.
        In order to use test transactions with Ecto SQL, you need to
        configure your repository to use #{inspect Sandbox}:

            pool: #{inspect Sandbox}
        """
    end
  end

  defp test_transaction(pool, fun, log, opts) do
    timeout = Keyword.fetch!(opts, :timeout)
    case apply(Sandbox, fun, [pool, log, opts, timeout]) do
      :ok ->
        :ok
      {:error, :sandbox} when fun == :begin ->
        raise "cannot begin test transaction because we are already inside one"
    end
  end

  ## Worker

  @doc false
  def start_link(connection, adapter, _repo, opts) do
    unless Code.ensure_loaded?(connection) do
      raise """
      could not find #{inspect connection}.

      Please verify you have added #{inspect adapter} as a dependency:

          {#{inspect adapter}, ">= 0.0.0"}

      And remember to recompile Ecto afterwards by cleaning the current build:

          mix deps.clean ecto
      """
    end

    {pool, opts} = Keyword.pop(opts, :pool)
    pool.start_link(connection, opts)
  end

  ## Types

  @doc false
  def load({:embed, _} = type, data, loader),
    do: Ecto.Type.load(type, data, fn
          {:embed, _} = type, value -> loader.(type, value)
          type, value -> Ecto.Type.cast(type, value)
        end)
  def load(:binary_id, data, loader),
    do: Ecto.Type.load(Ecto.UUID, data, loader)
  def load(type, data, loader),
    do: Ecto.Type.load(type, data, loader)

  @doc false
  def dump({:embed, _} = type, data, dumper),
    do: Ecto.Type.dump(type, data, fn
          {:embed, _} = type, value -> dumper.(type, value)
          _type, value -> {:ok, value}
        end)
  def dump(:binary_id, data, dumper),
    do: Ecto.Type.dump(Ecto.UUID, data, dumper)
  def dump(type, data, dumper),
    do: Ecto.Type.dump(type, data, dumper)

  @doc false
  def bingenerate(key) do
    {:ok, value} = Ecto.UUID.dump(Ecto.UUID.generate)
    {[{key, value}], [{key, unwrap(value)}]}
  end

  defp unwrap(%Ecto.Query.Tagged{value: value}), do: value
  defp unwrap(value), do: value

  ## Query

  @doc false
  def execute(repo, _meta, prepared, params, nil, opts) do
    %{rows: rows, num_rows: num} = query!(repo, prepared, params, nil, opts)
    {num, rows}
  end

  def execute(repo, meta, prepared, params, preprocess, opts) do
    fields = count_fields(meta.select.fields, meta.sources)
    mapper = &process_row(&1, preprocess, fields)
    %{rows: rows, num_rows: num} = query!(repo, prepared, params, mapper, opts)
    {num, rows}
  end

  @doc false
  def model(repo, conn, sql, values, returning, opts) do
    case query(repo, sql, values, nil, opts) do
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

  defp count_fields(fields, sources) do
    Enum.map fields, fn
      {:&, _, [idx]} = field ->
        {_source, model} = elem(sources, idx)
        {field, length(model.__schema__(:fields))}
      field ->
        {field, 0}
    end
  end

  defp process_row(row, preprocess, fields) do
    Enum.map_reduce(fields, row, fn
      {field, 0}, [h|t] ->
        {preprocess.(field, h, nil), t}
      {field, count}, acc ->
        case split_and_not_nil(acc, count, true, []) do
          {nil, rest} -> {nil, rest}
          {val, rest} -> {preprocess.(field, val, nil), rest}
        end
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
    {pool_mod, pool, timeout} = repo.__pool__
    opts    = Keyword.put_new(opts, :timeout, timeout)
    timeout = Keyword.fetch!(opts, :timeout)

    transaction = fn
      :opened, ref, {mod, _conn}, queue_time ->
        mode = transaction_mode(pool_mod, pool, timeout)
        transaction(repo, ref, mod, mode, queue_time, timeout, opts, fun)
      :already_open, ref, _, _ ->
        {{:return, Pool.with_rollback(:already_open, ref, fun)}, nil}
    end

    case Pool.transaction(pool_mod, pool, timeout, transaction) do
      {{:return, result}, entry} ->
        log(repo, entry)
        result
      {{:raise, class, reason, stack}, entry} ->
        log(repo, entry)
        :erlang.raise(class, reason, stack)
      {{:error, err}, entry} ->
        log(repo, entry)
        raise err
      {:error, :noconnect} ->
        exit({:noconnect, {__MODULE__, :transaction, [repo, opts, fun]}})
      {:error, :noproc} ->
        raise ArgumentError, "repo #{inspect repo} is not started, " <>
                             "please ensure it is part of your supervision tree"
    end
  end

  @doc false
  def rollback(repo, value) do
    {pool_mod, pool, _timeout} = repo.__pool__
    Pool.rollback(pool_mod, pool, value)
  end

  defp transaction_mode(Sandbox, pool, timeout), do: Sandbox.mode(pool, timeout)
  defp transaction_mode(_, _, _), do: :raw

  defp transaction(repo, ref, mod, mode, queue_time, timeout, opts, fun) do
    case begin(repo, mod, mode, queue_time, opts) do
      {{:ok, _}, entry} ->
        safe = fn -> log(repo, entry); fun.() end
        case Pool.with_rollback(:opened, ref, safe) do
          {:ok, _} = ok ->
            commit(repo, ref, mod, mode, timeout, opts, {:return, ok})
          {:error, _} = error ->
            rollback(repo, ref, mod, mode, timeout, opts, {:return, error})
          {:raise, _kind, _reason, _stack} = raise ->
            rollback(repo, ref, mod, mode, timeout, opts, raise)
        end
      {{:error, _err}, _entry} = error ->
        Pool.break(ref, timeout)
        error
      :noconnect ->
        {:error, :noconnect}
    end
  end

  defp begin(repo, mod, mode, queue_time, opts) do
    sql = begin_sql(mod, mode)
    query(repo, sql, [], queue_time, nil, opts)
  end

  defp begin_sql(mod, :raw),     do: mod.begin_transaction
  defp begin_sql(mod, :sandbox), do: mod.savepoint "ecto_trans"

  defp commit(repo, ref, mod, :raw, timeout, opts, result) do
    case query(repo, mod.commit, [], nil, nil, opts) do
      {{:ok, _}, entry} ->
        {result, entry}
      {{:error, _}, _entry} = error ->
        Pool.break(ref, timeout)
        error
      :noconnect ->
        {result, nil}
    end
  end

  defp commit(_repo, _ref, _mod, _mode, _timeout, _opts, result) do
    {result, nil}
  end

  defp rollback(repo, ref, mod, mode, timeout, opts, result) do
    sql = rollback_sql(mod, mode)

    case query(repo, sql, [], nil, nil, opts) do
      {{:ok, _}, entry} ->
        {result, entry}
      {{:error, _}, _entry} = error ->
        Pool.break(ref, timeout)
        error
      :noconnect ->
        {result, nil}
    end
  end

  defp rollback_sql(mod, :raw), do: mod.rollback
  defp rollback_sql(mod, :sandbox) do
    mod.rollback_to_savepoint "ecto_trans"
  end
end
