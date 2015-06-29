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
      defmacro __before_compile__(env) do
        Ecto.Adapters.SQL.__before_compile__(env)
      end

      @doc false
      def start_link(repo, opts) do
        {:ok, _} = Application.ensure_all_started(@adapter)
        Ecto.Adapters.SQL.start_link(@conn, @adapter, repo, opts)
      end

      @doc false
      def stop(repo) do
        Ecto.Adapters.SQL.stop(repo)
      end

      ## Query

      @doc false
      def id_types(_repo) do
        %{binary_id: Ecto.UUID}
      end

      @doc false
      def all(repo, query, params, opts) do
        Ecto.Adapters.SQL.all(repo, @conn.all(query), query, params, id_types(repo), opts)
      end

      @doc false
      def update_all(repo, query, params, opts) do
        Ecto.Adapters.SQL.count_all(repo, @conn.update_all(query), params, opts)
      end

      @doc false
      def delete_all(repo, query, params, opts) do
        Ecto.Adapters.SQL.count_all(repo, @conn.delete_all(query), params, opts)
      end

      @doc false
      # Nil ids are generated in the database.
      def insert(repo, source, params, {key, :id, nil}, returning, opts) do
        insert(repo, source, params, nil, [key|returning], opts)
      end

      # Nil binary_ids are generated in the adapter.
      def insert(repo, source, params, {key, :binary_id, nil}, returning, opts) do
        {req, resp} = Ecto.Adapters.SQL.bingenerate(key, id_types(repo))
        case insert(repo, source, req ++ params, nil, returning, opts) do
          {:ok, values}     -> {:ok, resp ++ values}
          {:error, _} = err -> err
        end
      end

      def insert(repo, source, params, _autogenerate, returning, opts) do
        {fields, values} = :lists.unzip(params)
        sql = @conn.insert(source, fields, returning)
        Ecto.Adapters.SQL.model(repo, sql, values, returning, opts)
      end

      @doc false
      def update(repo, source, fields, filter, _autogenerate, returning, opts) do
        {fields, values1} = :lists.unzip(fields)
        {filter, values2} = :lists.unzip(filter)
        sql = @conn.update(source, fields, filter, returning)
        Ecto.Adapters.SQL.model(repo, sql, values1 ++ values2, returning, opts)
      end

      @doc false
      def delete(repo, source, filter, _autogenarate, opts) do
        {filter, values} = :lists.unzip(filter)
        Ecto.Adapters.SQL.model(repo, @conn.delete(source, filter, []), values, [], opts)
      end

      ## Transaction

      @doc false
      def transaction(repo, opts, fun) do
        Ecto.Adapters.SQL.transaction(repo, opts, fun)
      end

      @doc false
      def rollback(_repo, value) do
        throw {:ecto_rollback, value}
      end

      ## Migration

      @doc false
      def execute_ddl(repo, definition, opts) do
        sql = @conn.execute_ddl(definition)
        Ecto.Adapters.SQL.query(repo, sql, [], opts)
        :ok
      end

      @doc false
      def ddl_exists?(repo, object, opts) do
        sql = @conn.ddl_exists(object)
        %{rows: [{count}]} = Ecto.Adapters.SQL.query(repo, sql, [], opts)
        count > 0
      end

      defoverridable [all: 4, update_all: 4, delete_all: 4,
                      insert: 6, update: 7, delete: 5,
                      execute_ddl: 3, ddl_exists?: 3]
    end
  end

  alias Ecto.Adapters.Pool
  alias Ecto.Adapters.SQL.Sandbox

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

      iex> Ecto.Adapters.SQL.query(MyRepo, "SELECT $1 + $2", [40, 2])
      %{rows: [{42}], num_rows: 1}

  """
  @spec query(Ecto.Repo.t, String.t, [term], Keyword.t) ::
             %{rows: nil | [tuple], num_rows: non_neg_integer} | no_return
  def query(repo, sql, params, opts \\ []) do
    case query(repo, sql, params, nil, opts) do
      {{:ok, result}, entry} ->
        log(repo, entry)
        result
      {{:error, err}, entry} ->
        log(repo, entry)
        raise err
      :noconnect ->
        # :noconnect can never be the reason a call fails because
        # it is converted to {:nodedown, node}. This means the exit
        # reason can be easily identified.
        exit({:noconnect, {__MODULE__, :query, [repo, sql, params, opts]}})
    end
  end

  defp query(repo, sql, params, outer_queue_time, opts) do
    {pool_mod, pool, timeout} = repo.__pool__
    opts    = Keyword.put_new(opts, :timeout, timeout)
    timeout = Keyword.fetch!(opts, :timeout)
    log?    = Keyword.get(opts, :log, true)

    query_fun = fn({mod, conn}, inner_queue_time) ->
      query(mod, conn, inner_queue_time || outer_queue_time, sql, params, log?, opts)
    end

    case Pool.run(pool_mod, pool, timeout, query_fun) do
      {:ok, result} ->
        result
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
    {query_time, res} = :timer.tc(mod, :query, [conn, sql, params, opts])
    entry = %Ecto.LogEntry{query: sql, params: params, result: res,
                           query_time: query_time, queue_time: queue_time}
    {res, entry}
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
  def __before_compile__(env) do
    config   = Module.get_attribute(env.module, :config)
    timeout  = Keyword.get(config, :timeout, 5000)
    pool_mod = Keyword.get(config, :pool, Ecto.Adapters.Poolboy)

    quote do
      def __pool__ do
        {unquote(pool_mod), __MODULE__.Pool, unquote(timeout)}
      end
    end
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

    {pool_mod, pool, _} = repo.__pool__
    opts = opts
      |> Keyword.put(:timeout, Keyword.get(opts, :connect_timeout, 5000))
      |> Keyword.put(:name, pool)
      |> Keyword.put_new(:size, 10)

    pool_mod.start_link(connection, opts)
  end

  @doc false
  def stop(repo) do
    {pool_mod, pool, _} = repo.__pool__
    pool_mod.stop(pool)
  end

  ## Query

  @doc false
  def bingenerate(key, id_types) do
    %{binary_id: binary_id} = id_types
    {:ok, value} = binary_id.dump(binary_id.generate)
    {[{key, value}], [{key, unwrap(value)}]}
  end

  defp unwrap(%Ecto.Query.Tagged{value: value}), do: value
  defp unwrap(value), do: value

  @doc false
  def all(repo, sql, query, params, id_types, opts) do
    %{rows: rows} = query(repo, sql, params, opts)
    fields = extract_fields(query.select.fields, query.sources)
    Enum.map(rows, &process_row(&1, fields, id_types))
  end

  @doc false
  def count_all(repo, sql, params, opts) do
    %{num_rows: num} = query(repo, sql, params, opts)
    {num, nil}
  end

  @doc false
  def model(repo, sql, values, returning, opts) do
    case query(repo, sql, values, opts) do
      %{rows: nil, num_rows: 1} ->
        {:ok, []}
      %{rows: [values], num_rows: 1} ->
        {:ok, Enum.zip(returning, Tuple.to_list(values))}
      %{num_rows: 0} ->
        {:error, :stale}
    end
  end

  defp extract_fields(fields, sources) do
    Enum.map fields, fn
      {:&, _, [idx]} ->
        {_source, model} = pair = elem(sources, idx)
        {length(model.__schema__(:fields)), pair}
      _ ->
        {1, nil}
    end
  end

  defp process_row(row, fields, id_types) do
    Enum.map_reduce(fields, 0, fn
      {1, nil}, idx ->
        {elem(row, idx), idx + 1}
      {count, {source, model}}, idx ->
        if all_nil?(row, idx, count) do
          {nil, idx + count}
        else
          {model.__schema__(:load, source, idx, row, id_types), idx + count}
        end
    end) |> elem(0)
  end

  defp all_nil?(_tuple, _idx, 0), do: true
  defp all_nil?(tuple, idx, _count) when elem(tuple, idx) != nil, do: false
  defp all_nil?(tuple, idx, count), do: all_nil?(tuple, idx + 1, count - 1)

  ## Transactions

  @doc false
  def transaction(repo, opts, fun) do
    {pool_mod, pool, timeout} = repo.__pool__
    opts    = Keyword.put_new(opts, :timeout, timeout)
    timeout = Keyword.fetch!(opts, :timeout)

    trans_fun = fn(ref, {mod, _conn}, depth, queue_time) ->
      mode = transaction_mode(pool_mod, pool, timeout)
      transaction(repo, ref, mod, mode, depth, queue_time, timeout, opts, fun)
    end

    case Pool.transaction(pool_mod, pool, timeout, trans_fun) do
      {:ok, {{:return, result}, entry}} ->
        log(repo, entry)
        result
      {:ok, {{:raise, class, reason, stack}, entry}} ->
        log(repo, entry)
        :erlang.raise(class, reason, stack)
      {:ok, {{:error, err}, entry}} ->
        log(repo, entry)
        raise err
      {:ok, :noconnect} ->
        exit({:noconnect, {__MODULE__, :transaction, [repo, opts, fun]}})
      {:error, :noproc} ->
        raise ArgumentError, "repo #{inspect repo} is not started, " <>
                             "please ensure it is part of your supervision tree"
    end
  end

  defp transaction_mode(Sandbox, pool, timeout), do: Sandbox.mode(pool, timeout)
  defp transaction_mode(_, _, _), do: :raw

  defp transaction(repo, ref, mod, mode, depth, queue_time, timeout, opts, fun) do
    case begin(repo, mod, mode, depth, queue_time, opts) do
      {{:ok, _}, entry} ->
        try do
          log(repo, entry)
          value = fun.()
          commit(repo, ref, mod, mode, depth, timeout, opts, {:return, {:ok, value}})
        catch
          :throw, {:ecto_rollback, value} ->
            res = {:return, {:error, value}}
            rollback(repo, ref, mod, mode, depth, nil, timeout, opts, res)
          class, reason ->
            stack = System.stacktrace()
            res = {:raise, class, reason, stack}
            rollback(repo, ref, mod, mode, depth, nil, timeout, opts, res)
        end
      {{:error, _err}, _entry} = error ->
        Pool.break(ref, timeout)
        error
      :noconnect ->
        :noconnect
    end
  end

  defp begin(repo, mod, mode, depth, queue_time, opts) do
    sql = begin_sql(mod, mode, depth)
    query(repo, sql, [], queue_time, opts)
  end

  defp begin_sql(mod, :raw, 1), do: mod.begin_transaction
  defp begin_sql(mod, :raw, :sandbox), do: mod.savepoint "ecto_sandbox"
  defp begin_sql(mod, _, depth), do: mod.savepoint "ecto_#{depth}"

  defp commit(repo, ref, mod, :raw, 1, timeout, opts, result) do
    case query(repo, mod.commit, [], nil, opts) do
      {{:ok, _}, entry} ->
        {result, entry}
      {{:error, _}, _entry} = error ->
        Pool.break(ref, timeout)
        error
      :noconnect ->
        {result, nil}
    end
  end

  defp commit(_repo, _ref, _mod, _mode, _depth, _timeout, _opts, result) do
    {result, nil}
  end

  defp rollback(repo, ref, mod, mode, depth, queue_time, timeout, opts, result) do
    sql = rollback_sql(mod, mode, depth)

    case query(repo, sql, [], queue_time, opts) do
      {{:ok, _}, entry} ->
        {result, entry}
      {{:error, _}, _entry} = error ->
        Pool.break(ref, timeout)
        error
      :noconnect ->
        {result, nil}
    end
  end

  defp rollback_sql(mod, :raw, 1), do: mod.rollback
  defp rollback_sql(mod, :sandbox, :sandbox) do
    mod.rollback_to_savepoint "ecto_sandbox"
  end
  defp rollback_sql(mod, _, depth) do
    mod.rollback_to_savepoint "ecto_#{depth}"
  end
end
