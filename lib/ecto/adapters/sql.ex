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

  See `Ecto.Adapters.Worker` for connection pooling and
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
      def update_all(repo, query, values, params, opts) do
        Ecto.Adapters.SQL.count_all(repo, @conn.update_all(query, values), params, opts)
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

      defoverridable [all: 4, update_all: 5, delete_all: 4,
                      insert: 6, update: 7, delete: 5,
                      execute_ddl: 3, ddl_exists?: 3]
    end
  end

  alias Ecto.Adapters.Worker

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
    key  = {:ecto_transaction_info, pool}
    opts = Keyword.put_new(opts, :timeout, timeout)

    case Process.get(key) do
      %{conn: nil} ->
        # :noconnect can never be the reason a call fails because
        # it is converted to {:nodedown, node}. This means the exit
        # reason can be easily identified.
        exit({:noconnect, {__MODULE__, :query, [repo, sql, params, opts]}})
      %{module: module, conn: conn} ->
        query!(repo, module, conn, sql, params, nil, opts)
      nil ->
        pool_query!(repo, pool, sql, params, opts)
    end
  end

  defp pool_query!(repo, pool, sql, params, opts) do
    timeout = Keyword.get(opts, :timeout)

    {queue_time, {query_time, res}} =
      pool_transaction(repo, pool, timeout, fn time, worker ->
        {module, conn} = Worker.ask!(worker, timeout)
        {time, :timer.tc(module, :query, [conn, sql, params, opts])}
      end)

    log_and_check(repo, sql, params, query_time, queue_time, opts, res)
  end

  defp query!(repo, module, conn, sql, params, queue_time, opts) do
    {query_time, res} = :timer.tc(module, :query, [conn, sql, params, opts])
    log_and_check(repo, sql, params, query_time, queue_time, opts, res)
  end

  defp log_and_check(repo, sql, params, query_time, queue_time, opts, res) do
    if Keyword.get(opts, :log, true) do
      repo.log(%Ecto.LogEntry{query: sql, params: params, result: res,
                              query_time: query_time, queue_time: queue_time})
    end

    case res do
      {:ok, reply}  -> reply
      {:error, err} -> raise err
    end
  end

  @doc ~S"""
  Starts a transaction for test.

  This function work by starting a transaction and storing the connection
  back in the pool with an open transaction. On every test, we restart
  the test transaction rolling back to the appropriate savepoint.

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
    start_test_transaction(:begin, repo, opts)
  end

  @doc """
  Restarts a test transaction, see `begin_test_transaction/2`.
  """
  @spec restart_test_transaction(Ecto.Repo.t, Keyword.t) :: :ok
  def restart_test_transaction(repo, opts \\ []) do
    start_test_transaction(:restart, repo, opts)
  end

  defp start_test_transaction(event, repo, opts) do
    {pool, timeout} = repo.__pool__
    opts = Keyword.put_new(opts, :timeout, timeout)
    timeout = Keyword.get(opts, :timeout)

    if Process.get({:ecto_transaction_info, pool}) do
      raise "cannot #{event} test transaction because we are already inside a regular transaction"
    end

    pool_transaction(repo, pool, timeout, fn time, worker ->
      case Worker.sandbox_transaction(worker, timeout) do
        {:ok, {module, conn}} ->
          begin_sandbox!(repo, module, conn, time, opts)
        {:sandbox, {module, conn}} when event == :restart ->
          restart_sandbox!(repo, module, conn, time, opts)
        {:sandbox, _} when event == :begin ->
          raise "cannot begin test transaction because we are already inside one"
        {:error, err} ->
          raise err
      end
    end)

    :ok
  end

  defp begin_sandbox!(repo, module, conn, queue_time, opts) do
    query!(repo, module, conn, module.begin_transaction, [], queue_time, opts)
    query!(repo, module, conn, module.savepoint("ecto_sandbox"), [], nil, opts)
  end

  defp restart_sandbox!(repo, module, conn, queue_time, opts) do
    query!(repo, module, conn, module.rollback_to_savepoint("ecto_sandbox"), [], queue_time, opts)
  end

  @spec rollback_test_transaction(Ecto.Repo.t, Keyword.t) :: :ok
  def rollback_test_transaction(repo, opts \\ []) do
    {pool, timeout} = repo.__pool__
    opts = Keyword.put_new(opts, :timeout, timeout)
    timeout = Keyword.get(opts, :timeout)

    pool_transaction(repo, pool, timeout, fn time, worker ->
      worker_fuse(pool, worker, timeout, fn ->
        {module, conn} = Worker.ask!(worker, timeout)
        query!(repo, module, conn, module.rollback, [], time, opts)
        Worker.close_transaction(worker, timeout)
      end)
    end)

    :ok
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
    {pool, timeout} = repo.__pool__

    key     = {:ecto_transaction_info, pool}
    opts    = Keyword.put_new(opts, :timeout, timeout)
    timeout = Keyword.get(opts, :timeout)

    {queue_time, _worker} =
      open_transaction(key, repo, pool, timeout)

    try do
      begin_transaction(key, repo, pool, queue_time, timeout, opts)
      value = fun.()
      commit_transaction(key, repo, pool, timeout, opts)
      {:ok, value}
    catch
      :throw, {:ecto_rollback, value} ->
        rollback_transaction(key, repo, pool, timeout, opts)
        {:error, value}
      kind, reason ->
        stacktrace = System.stacktrace
        rollback_transaction(key, repo, pool, timeout, opts)
        :erlang.raise(kind, reason, stacktrace)
    after
      maybe_checkin(key, pool)
    end
  end

  defp open_transaction(key, repo, pool, timeout) do
    case Process.get(key) do
      %{worker: worker} ->
        {nil, worker}
      nil ->
        {time, worker} = checkout(repo, pool, timeout)

        pool_fuse(pool, worker, fn ->
          case Worker.open_transaction(worker, timeout) do
            {:ok, {module, conn}} ->
              # We got permission to start a transaction
              Process.put(key, %{worker: worker, module: module, conn: conn,
                                 counter: 0, threshold: 0})
            {:sandbox, {module, conn}} ->
              # Inside sandbox we only emit savepoints
              Process.put(key, %{worker: worker, module: module, conn: conn,
                                 counter: 1, threshold: 1})
            {:error, err} ->
              raise err
          end
        end)

        {time, worker}
    end
  end

  defp begin_transaction(key, repo, pool, queue_time, timeout, opts) do
    %{worker: worker, module: module,
      conn: conn, counter: counter} = info = Process.get(key)

    query =
      case counter do
        0 -> module.begin_transaction
        _ -> module.savepoint "ecto_#{counter}"
      end

    # We need to bump the counter before going into
    # worker_fuse because if it fails, we are going
    # to still invoke the rollback so the counter
    # must be correct.
    Process.put(key, %{info | counter: counter + 1})

    worker_fuse(pool, worker, timeout, fn ->
      query!(repo, module, conn, query, [], queue_time, opts)
    end)
  end

  defp commit_transaction(key, repo, pool, timeout, opts) do
    %{worker: worker, module: module,
      conn: conn, counter: counter} = Process.get(key)
    counter = counter - 1

    if conn && counter == 0 do
      worker_fuse(pool, worker, timeout, fn ->
        query!(repo, module, conn, module.commit, [], nil, opts)
        Worker.close_transaction(worker, timeout)
      end)
    end
  end

  defp rollback_transaction(key, repo, pool, timeout, opts) do
    %{worker: worker, module: module, conn: conn, counter: counter} = Process.get(key)
    counter = counter - 1

    query = case counter do
      0 -> module.rollback
      _ -> module.rollback_to_savepoint("ecto_#{counter}")
    end

    worker_fuse(pool, worker, timeout, fn ->
      # We may lose the connection in case worker_fuse was triggered.
      # So we need to check to avoid further raising on rollback.
      if conn do
        query!(repo, module, conn, query, [], nil, opts)
      end

      # If counter is 0, time to close the transaction.
      if counter == 0 do
        Worker.close_transaction(worker, timeout)
      end
    end)
  end

  # Note maybe_checkin needs to re-read the process dictionary
  # because worker_fuse may have cleaned up the connection and
  # we should not put it back.
  defp maybe_checkin(key, pool) do
    %{worker: worker, counter: counter, threshold: threshold} = info = Process.get(key)
    counter = counter - 1

    if counter == threshold do
      Process.delete(key)
      :poolboy.checkin(pool, worker)
    else
      Process.put(key, %{info | counter: counter})
    end
  end

  ## Helpers

  defp checkout(repo, pool, timeout) do
    try do
      :timer.tc(:poolboy, :checkout, [pool, true, timeout])
    catch
      :exit, {:noproc, _} ->
        raise ArgumentError, "repo #{inspect repo} is not started, " <>
                             "please ensure it is part of your supervision tree"
    end
  end

  defp pool_transaction(repo, pool, timeout, fun) do
    {time, worker} = checkout(repo, pool, timeout)

    try do
      fun.(time, worker)
    after
      :ok = :poolboy.checkin(pool, worker)
    end
  end

  # A fuse performs clean up only if something goes wrong.
  # They are different from transactions that always clean up.

  defp pool_fuse(pool, worker, fun) do
    fun.()
  catch
    kind, reason ->
      stack = System.stacktrace()
      :poolboy.checkin(pool, worker)
      :erlang.raise(kind, reason, stack)
  end

  defp worker_fuse(pool, worker, timeout, fun) do
    fun.()
  catch
    kind, reason ->
      # If it fails, we don't know the connection state
      # so we need to break the transaction and remove
      # the connection from transaction info.
      stack = System.stacktrace()
      key   = {:ecto_transaction_info, pool}
      Process.put(key, %{Process.get(key) | conn: nil})
      Worker.break_transaction(worker, timeout)
      :erlang.raise(kind, reason, stack)
  end
end
