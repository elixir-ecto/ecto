defmodule Ecto.Adapters.SQL do
  @moduledoc """
  Behaviour and implementation for SQL adapters.

  The implementation for SQL adapter provides a
  pooled based implementation of SQL and also expose
  a query function to developers.

  Developers that use `Ecto.Adapters.SQL` should implement
  the connection module with specifics on how to connect
  to the database and also how to translate the queries
  to SQL. See `Ecto.Adapters.SQL.Connection` for more info.
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
        Ecto.Adapters.SQL.start_link(@conn, @adapter, repo, opts)
      end

      @doc false
      def stop(repo) do
        Ecto.Adapters.SQL.stop(repo)
      end

      ## Query

      @doc false
      def all(repo, query, params, opts) do
        Ecto.Adapters.SQL.all(repo, @conn.all(query), query, params, opts)
      end

      @doc false
      def update_all(repo, query, values, params, opts) do
        Ecto.Adapters.SQL.count_all(repo, @conn.update_all(query, values), params, opts)
      end

      @doc false
      def delete_all(repo, query, params, opts) do
        Ecto.Adapters.SQL.count_all(repo, @conn.delete_all(query), params, opts)
      end

      @doc false
      def insert(repo, source, params, returning, opts) do
        {fields, values} = :lists.unzip(params)
        sql = @conn.insert(source, fields, returning)
        Ecto.Adapters.SQL.model(repo, sql, values, returning, opts)
      end

      @doc false
      def update(repo, source, fields, filter, returning, opts) do
        {fields, values1} = :lists.unzip(fields)
        {filter, values2} = :lists.unzip(filter)
        sql = @conn.update(source, fields, filter, returning)
        Ecto.Adapters.SQL.model(repo, sql, values1 ++ values2, returning, opts)
      end

      @doc false
      def delete(repo, source, filter, opts) do
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

      defoverridable [all: 4, update_all: 5, delete_all: 4,
                      insert: 5, update: 6, delete: 4,
                      execute_ddl: 3, ddl_exists?: 3]
    end
  end

  alias Ecto.Adapters.SQL.Worker

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
    {pool, timeout} = repo.__pool__
    opts = Keyword.put_new(opts, :timeout, timeout)

    log(repo, {:query, sql, params}, opts, fn ->
      query!(repo, pool, sql, params, opts)
    end)
  end

  defp query!(repo, pool, sql, params, opts) do
    key  = {:ecto_transaction_info, pool}
    timeout = opts[:timeout]

    case Process.get(key) do
      nil ->
        info = ask(repo, pool, timeout)
        do_query!(info, sql, params, opts, timeout)
      info ->
        do_query!(key, info, sql, params, opts, timeout)
    end
  end

  defp do_query!(%{module: module, conn: conn} = info, sql, params, opts, timeout) do
    try do
      apply(module, :query, [conn, sql, params, opts])
    catch
      class, type ->
        stack = System.stacktrace()
        done_and_disconnect(info, timeout)
        :erlang.raise(class, type, stack)
    else
      {:ok, result} ->
        done(info)
        result
      {:error, err} ->
        done(info)
        raise err
    end
  end

  defp do_query!(key, %{conn: nil} = info, sql, params, opts, timeout) do
    # :noconnect can never be the reason a call fails because it is converted to
    # {:nodedown, node}. This means the exit reason can be easily identified.
    args = [key, info, sql, params, opts, timeout]
    exit({:noconnect, {__MODULE__, :query!, args}})
  end
  defp do_query!(key, %{module: module, conn: conn} = info, sql, params, opts, timeout) do
    try do
      apply(module, :query, [conn, sql, params, opts])
    catch
      class, type ->
        stack = System.stacktrace()
        disconnect(key, info, timeout)
        :erlang.raise(class, type, stack)
    else
      {:ok, result} ->
        result
      {:error, err} ->
        raise err
    end
  end

  defp disconnect(key, info, timeout) do
    info = %{info | conn: nil}
    _ = Process.put(key, info)
    done_and_disconnect(info, timeout)
  end

  defp log(repo, tuple, opts, fun) do
    if Keyword.get(opts, :log, true) do
      repo.log(tuple, fun)
    else
      fun.()
    end
  end

  defp ask(repo, pool, timeout) do
    worker = checkout(repo, pool, timeout)
    try do
      Worker.ask(worker, timeout)
    catch
      :exit, {:timeout, _} = reason ->
        try do
          Worker.cancel(worker, timeout)
        after
          :poolboy.checkin(pool, worker)
          :erlang.raise(:exit, reason, System.stacktrace())
        end
      class, reason ->
        :poolboy.checkin(pool, worker)
        :erlang.raise(class, reason, System.stacktrace())
    else
      {:ok, {module, conn, ref, trans}} ->
        %{pool: pool, worker: worker, module: module, conn: conn, ref: ref,
          transactions: trans, depth: 0}
      {:error, err} ->
        raise err
    end
  end

  defp checkout(repo, pool, timeout) do
    try do
      :poolboy.checkout(pool, true, timeout)
    catch
      :exit, {:noproc, _} ->
        raise ArgumentError, "repo #{inspect repo} is not started, " <>
                             "please ensure it is part of your supervision tree"
    end
  end

  defp done(%{conn: nil}) do
    :ok
  end
  defp done(%{pool: pool, worker: worker, ref: ref, transactions: trans}) do
    Worker.done(worker, ref, trans)
    :poolboy.checkin(pool, worker)
  end

  defp done_and_disconnect(%{conn: nil}, _) do
    :ok
  end
  defp done_and_disconnect(%{pool: pool, worker: worker, ref: ref}, timeout) do
     Worker.stop(worker, ref, timeout)
    :poolboy.checkin(pool, worker)
  end

  @doc ~S"""
  Starts a transaction for test.

  This function work by starting a transaction and storing the connection
  back in the pool with an open transaction. At the end of the test, the
  transaction must be rolled back with `rollback_test_transaction`,
  reverting all data added during tests.

  **IMPORTANT:** Test transactions only work if the connection pool has
  size of 1 and does not support any overflow.

  ## Example

  The first step is to configure your database pool to have size of
  1 and no max overflow. You set those options in your `config/config.exs`:

      config :my_app, Repo,
        size: 1,
        max_overflow: 0

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
          assert %Post{} = TestRepo.insert(%Post{})
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
          assert %Post{} = TestRepo.insert(%Post{})
        end
      end

  """
  @spec begin_test_transaction(Ecto.Repo.t, Keyword.t) :: :ok
  def begin_test_transaction(repo, opts \\ []) do
    worker_query!(repo, &Worker.begin_test_transaction/4, opts)
  end

  @doc """
  Restarts a test transaction, see `begin_test_transaction/2`.
  """
  @spec restart_test_transaction(Ecto.Repo.t, Keyword.t) :: :ok
  def restart_test_transaction(repo, opts \\ []) do
    worker_query!(repo, &Worker.restart_test_transaction/4, opts)
  end

  @doc """
  Ends a test transaction, see `begin_test_transaction/2`.
  """
  @spec rollback_test_transaction(Ecto.Repo.t, Keyword.t) :: :ok
  def rollback_test_transaction(repo, opts \\ []) do
    worker_query!(repo, &Worker.rollback_test_transaction/4, opts)
  end

  defp worker_query!(repo, fun, opts) do
    {pool, timeout} = repo.__pool__
    opts            = Keyword.put_new(opts, :timeout, timeout)
    timeout         = Keyword.fetch!(opts, :timeout)

    %{worker: worker, ref: ref, transactions: trans} = info = ask(repo, pool, timeout)
    try do
      fun.(worker, ref, trans, opts)
    else
      {:ok, trans} ->
        done(%{info | transactions: trans})
      {:error, err} ->
        done_and_disconnect(info, timeout)
        raise err
    catch
      class, reason ->
        done_and_disconnect(info, timeout)
        :erlang.raise(class, reason, System.stacktrace())
    end
  end

  ## Worker

  @doc false
  def __before_compile__(env) do
    timeout =
      env.module
      |> Module.get_attribute(:config)
      |> Keyword.get(:timeout, 5000)

    quote do
      def __pool__ do
        {__MODULE__.Pool, unquote(timeout)}
      end
    end
  end

  @doc false
  def start_link(connection, adapter, repo, opts) do
    {pool_opts, worker_opts} = split_opts(repo, opts)

    unless Code.ensure_loaded?(connection) do
      raise """
      could not find #{inspect connection}.

      Please verify you have added #{inspect adapter} as a dependency:

          {#{inspect adapter}, ">= 0.0.0"}

      And remember to recompile Ecto afterwards by cleaning the current build:

          mix deps.clean ecto
      """
    end

    :poolboy.start_link(pool_opts, {connection, worker_opts})
  end

  @doc false
  def stop(repo) do
    :poolboy.stop elem(repo.__pool__, 0)
  end

  defp split_opts(repo, opts) do
    pool_name = elem(repo.__pool__, 0)
    {pool_opts, worker_opts} = Keyword.split(opts, [:size, :max_overflow])

    pool_opts = pool_opts
      |> Keyword.put_new(:size, 10)
      |> Keyword.put_new(:max_overflow, 0)

    pool_opts =
      [name: {:local, pool_name},
       worker_module: Worker] ++ pool_opts

    worker_opts = worker_opts
      |> Keyword.put(:timeout, Keyword.get(worker_opts, :connect_timeout, 5000))

    {pool_opts, worker_opts}
  end

  ## Query

  @doc false
  def all(repo, sql, query, params, opts) do
    %{rows: rows} = query(repo, sql, params, opts)
    fields = extract_fields(query.select.fields, query.sources)
    Enum.map(rows, &process_row(&1, fields))
  end

  @doc false
  def count_all(repo, sql, params, opts) do
    %{num_rows: num} = query(repo, sql, params, opts)
    num
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

  defp process_row(row, fields) do
    Enum.map_reduce(fields, 0, fn
      {1, nil}, idx ->
        {elem(row, idx), idx + 1}
      {count, {source, model}}, idx ->
        if all_nil?(row, idx, count) do
          {nil, idx + count}
        else
          {model.__schema__(:load, source, idx, row), idx + count}
        end
    end) |> elem(0)
  end

  defp all_nil?(_tuple, _idx, 0), do: true
  defp all_nil?(tuple, idx, _count) when elem(tuple, idx) != nil, do: false
  defp all_nil?(tuple, idx, count), do: all_nil?(tuple, idx + 1, count - 1)

  ## Transactions

  @doc false
  def transaction(repo, opts, fun) do
    {pool, timeout} = repo.__pool__

    opts    = Keyword.put_new(opts, :timeout, timeout)
    timeout = Keyword.fetch!(opts, :timeout)
    key     = {:ecto_transaction_info, pool}

    case Process.get(key) do
      nil ->
        begin_transaction(repo, pool, key, fun, opts, timeout)
      info ->
        transaction(repo, key, info, fun, opts, timeout)
    end
  end

  defp begin_transaction(repo, pool, key, fun, opts, timeout) do
    info = ask(repo, pool, timeout)
    _ = Process.put(key, info)
    try do
      transaction(repo, key, info, fun, opts, timeout)
    after
      done(Process.delete(key))
    end
  end

  defp transaction(repo, key, info, fun, opts, timeout) do
    try do
      do_begin(repo, key, info, opts, timeout)
      fun.()
    catch
      :throw, {:ecto_rollback, value} ->
        do_rollback(repo, key, Process.get(key), opts, timeout)
        {:error, value}
      type, term ->
        stacktrace = System.stacktrace
        do_rollback(repo, key, Process.get(key), opts, timeout)
        :erlang.raise(type, term, stacktrace)
    else
      value ->
        do_commit(repo, key, Process.get(key), opts, timeout)
        {:ok, value}
    end
  end

  defp do_begin(repo, key, %{transactions: [], depth: 0, module: module} = info,
  opts, timeout) do
    info = %{info | transactions: [next: :transaction], depth: 1}
    _ = Process.put(key, info)
    query = apply(module, :begin_transaction, [])
    log(repo, {:query, query, []}, opts, fn ->
      begin_query!(key, info, query, [], opts, timeout)
    end)
    :ok
  end
  defp do_begin(repo, key, %{transactions: [_|_] = trans, depth: n, module: module} = info,
  opts, timeout) do
    savepoint = "ecto_#{n}"
    n = n + 1
    query = apply(module, :savepoint, [savepoint])
    info = %{info | transactions: [next: {:savepoint, savepoint}] ++ trans, depth: n}
    _ = Process.put(key, info)
    log(repo, {:query, query, []}, opts, fn ->
      begin_query!(key, info, query, [], opts, timeout)
    end)
    :ok
  end

  defp do_rollback(_, key, %{conn: nil, transactions: trans, depth: n} = info, _, _) do
    info = %{info | transactions: tl(trans), depth: n-1}
    _ = Process.put(key, info)
    :ok
  end
  defp do_rollback(_, key, %{transactions: [{:next, _} | trans], depth: n} = info, _, _) do
    info = %{info | transactions: trans, depth: n-1}
    _ = Process.put(key, info)
    :ok
  end
  defp do_rollback(repo, key, %{transactions: [:transaction], depth: 1, module: module} = info,
  opts, timeout) do
    info = %{info | transactions: [], depth: 0}
    _ = Process.put(key, info)
    query = apply(module, :rollback, [])
    log(repo, {:query, query, []}, opts, fn ->
      transaction_query!(key, info, query, [], opts, timeout)
    end)
    :ok
  end
  defp do_rollback(repo, key, %{transactions: [{:savepoint, savepoint} | trans], depth: n, module: module} = info,
  opts, timeout) do
    info = %{info | transactions: trans, depth: n-1}
    _ = Process.put(key, info)
    query = apply(module, :rollback_to_savepoint, [savepoint])
    log(repo, {:query, query, []}, opts, fn ->
      transaction_query!(key, info, query, [], opts, timeout)
    end)
    :ok
  end

  defp do_commit(_, key, %{conn: nil, transactions: trans, depth: n} = info, _, _) do
    info = %{info | transactions: tl(trans), depth: n-1}
    _ = Process.put(key, info)
    :ok
  end
  defp do_commit(_, key, %{transactions: [{:next, _} | trans], depth: n} = info, _, _) do
    info = %{info | transactions: trans, depth: n-1}
    _ = Process.put(key, info)
    :ok
  end
  defp do_commit(repo, key, %{transactions: [:transaction], depth: 1, module: module} = info,
  opts, timeout) do
    info = %{info | transactions: [], depth: 0}
    _ = Process.put(key, info)
    query = apply(module, :commit, [])
    log(repo, {:query, query, []}, opts, fn ->
      transaction_query!(key, info, query, [], opts, timeout)
    end)
    :ok
  end
  defp do_commit(_, key, %{transactions: [{:savepoint, _} | trans], depth: n} = info, _, _) do
    info = %{info | transactions: trans, depth: n-1}
    _ = Process.put(key, info)
    :ok
  end

  defp begin_query!(key, %{module: module, conn: conn,
    transactions: [{:next, transaction} | trans]} = info,
  sql, params, opts, timeout) do
    try do
      apply(module, :query, [conn, sql, params, opts])
    catch
      class, type ->
        stack = System.stacktrace()
        disconnect(key, info, timeout)
        :erlang.raise(class, type, stack)
    else
      {:ok, result} ->
        _ = Process.put(key, %{info | transactions: [transaction | trans]})
        result
      {:error, err} ->
        raise err
    end
  end

  defp transaction_query!(key, %{module: module, conn: conn} = info, sql, params,
  opts, timeout) do
    try do
      apply(module, :query, [conn, sql, params, opts])
    catch
      class, type ->
        stack = System.stacktrace()
        disconnect(key, info, timeout)
        :erlang.raise(class, type, stack)
    else
      {:ok, result} ->
        result
      {:error, err} ->
        disconnect(key, info, timeout)
        raise err
    end
  end
end
