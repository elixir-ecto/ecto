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
        %{binary_id: binary_id} = id_types(repo)
        autogenerate = [{key, binary_id.bingenerate}]
        case insert(repo, source, autogenerate ++ params, nil, returning, opts) do
          {:ok, values}     -> {:ok, autogenerate ++ values}
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

  alias Ecto.Adapters.Poolboy

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
    opts            = Keyword.put_new(opts, :timeout, timeout)
    timeout         = Keyword.fetch!(opts, :timeout)
    log?            = Keyword.get(opts, :log, true)


    query_fun = fn(ref, _mode, _depth, queue_time) ->
      query(ref, queue_time, sql, params, log?, timeout, opts)
    end

    case Poolboy.transaction(pool, timeout, query_fun) do
      {:ok, {{:ok, result}, entry}} ->
        log(repo, entry)
        result
      {:ok, {{:error, err}, entry}} ->
        log(repo, entry)
        raise err
      {:ok, :noconnect} ->
        # :noconnect can never be the reason a call fails because
        # it is converted to {:nodedown, node}. This means the exit
        # reason can be easily identified.
        exit({:noconnect, {__MODULE__, :query, [repo, sql, params, opts]}})
      {:error, :noproc} ->
        raise ArgumentError, "repo #{inspect repo} is not started, " <>
                             "please ensure it is part of your supervision tree"
    end
  end

  defp query(ref, queue_time, sql, params, log?, timeout, opts) do
    case Poolboy.connection(ref) do
      {:ok, {mod, conn}} ->
        query(ref, mod, conn, queue_time, sql, params, log?, timeout, opts)
      {:error, :noconnect} ->
        :noconnect
    end
  end

  defp query(ref, mod, conn, _queue_time, sql, params, false, timeout, opts) do
    try do
      mod.query(conn, sql, params, opts)
    catch
      class, reason ->
        stack = System.stacktrace()
        Poolboy.disconnect(ref, timeout)
        :erlang.raise(class, reason, stack)
    else
      res ->
        {res, nil}
    end
  end
  defp query(ref, mod, conn, queue_time, sql, params, true, timeout, opts) do
    try do
      :timer.tc(mod, :query, [conn, sql, params, opts])
    catch
      class, reason ->
        stack = System.stacktrace()
        Poolboy.disconnect(ref, timeout)
        :erlang.raise(class, reason, stack)
    else
      {query_time, res} ->
        entry = %Ecto.LogEntry{query: sql, params: params, result: res,
                               query_time: query_time, queue_time: queue_time}
       {res, entry}
    end
  end

  defp log(_repo, nil), do: :ok
  defp log(repo, entry), do: repo.log(entry)

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

  defp test_transaction(event, repo, opts) do
    {pool, timeout} = repo.__pool__
    opts = Keyword.put_new(opts, :timeout, timeout)
    timeout = Keyword.get(opts, :timeout)

    trans_fun =
      fn(ref, :raw, 0, queue_time) when event in [:begin, :restart] ->
          begin_sandbox(repo, ref, queue_time, timeout, opts)
        (_ref, :raw, 0, _queue_time) when event === :rollback ->
          {:ok, nil}
        (_ref, :sandbox, 0, _queue_time) when event === :begin ->
          raise "cannot begin test transaction because we are already inside one"
        (ref, :sandbox, 0, queue_time) when event === :restart ->
          restart_sandbox(ref, queue_time, timeout, opts)
        (ref, :sandbox, 0, queue_time) when event === :rollback ->
          rollback_sandbox(ref, queue_time, timeout, opts)
        (_ref, _mode, _depth, _queue_time) ->
          raise "cannot #{event} test transaction because we are already inside a regular transaction"
      end

    case Poolboy.transaction(pool, timeout, trans_fun) do
      {:ok, {:ok, entry}} ->
        log(repo, entry)
        :ok
      {:ok, {{:error, err}, entry}} ->
        log(repo, entry)
        raise err
      {:ok, :noconnect} ->
        exit({:noconnect, {__MODULE__, :test_transaction, [event, repo, opts]}})
      {:error, :noproc} ->
        raise ArgumentError, "repo #{inspect repo} is not started, " <>
                             "please ensure it is part of your supervision tree"
    end
  end

  defp begin_sandbox(repo, ref, queue_time, timeout, opts) do
    log? = Keyword.get(opts, :log, true)
    case begin(ref, :raw, 0, queue_time, log?, timeout, opts) do
      {{:ok, _}, entry} ->
        try do
          log(repo, entry)
          savepoint_sandbox(ref, log?, timeout, opts)
        catch
          class, reason ->
            stack = System.stacktrace()
            Poolboy.disconnect(ref, timeout)
            :erlang.raise(class, reason, stack)
        end
      {{:error, _err}, _entry} = error ->
        Poolboy.disconnect(ref, timeout)
        error
    end
  end

  defp savepoint_sandbox(ref, log?, timeout, opts) do
    case begin(ref, :raw, :sandbox, nil, log?, timeout, opts) do
      {{:ok, _}, entry} ->
        _ = Poolboy.mode(ref, :sandbox, timeout)
        {:ok, entry}
      {{:error, _err}, _entry} = error ->
        Poolboy.disconnect(ref, timeout)
        error
    end
  end

  defp restart_sandbox(ref, queue_time, timeout, opts) do
    log? = Keyword.get(opts, :log, true)
    case rollback(ref, :sandbox, :sandbox, queue_time, log?, timeout, opts) do
      {{:ok, _}, entry} ->
        {:ok, entry}
      {{:error, _err}, _entry} = error ->
        Poolboy.disconnect(ref, timeout)
        error
    end
  end

  defp rollback_sandbox(ref, queue_time, timeout, opts) do
    log? = Keyword.get(opts, :log, true)
    case rollback(ref, :raw, 0, queue_time, log?, timeout, opts) do
      {{:ok, _}, entry} ->
        _ = Poolboy.mode(ref, :raw, timeout)
        {:ok, entry}
      {{:error, _err}, _entry} = error ->
        Poolboy.disconnect(ref, timeout)
        error
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
    unless Code.ensure_loaded?(connection) do
      raise """
      could not find #{inspect connection}.

      Please verify you have added #{inspect adapter} as a dependency:

          {#{inspect adapter}, ">= 0.0.0"}

      And remember to recompile Ecto afterwards by cleaning the current build:

          mix deps.clean ecto
      """
    end
    opts = opts
      |> Keyword.put(:timeout, Keyword.get(opts, :connect_timeout, 5000))
      |> Keyword.put(:name, elem(repo.__pool__, 0))

    Poolboy.start_link(connection, opts)
  end

  @doc false
  def stop(repo) do
    Poolboy.stop elem(repo.__pool__, 0)
  end

  ## Query

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
    opts            = Keyword.put_new(opts, :timeout, timeout)
    timeout         = Keyword.fetch!(opts, :timeout)

    trans_fun = fn(ref, mode, depth, queue_time) ->
      transaction(repo, ref, mode, depth, queue_time, timeout, opts, fun)
    end

    case Poolboy.transaction(pool, timeout, trans_fun) do
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

  defp transaction(repo, ref, mode, depth, queue_time, timeout, opts, fun) do
    log? = Keyword.get(opts, :log, true)
    case begin(ref, mode, depth, queue_time, log?, timeout, opts) do
      {{:ok, _}, entry} ->
        try do
          log(repo, entry)
          value = fun.()
          commit(ref, mode, depth, log?, timeout, opts, {:return, {:ok, value}})
        catch
          :throw, {:ecto_rollback, value} ->
            result = {:return, {:error, value}}
            rollback(ref, mode, depth, nil, log?, timeout, opts, result)
          class, reason ->
            stack = System.stacktrace()
            res = {:raise, class, reason, stack}
            rollback(ref, mode, depth, nil, log?, timeout, opts, res)
        end
      {{:error, _err}, _entry} = result ->
        Poolboy.disconnect(ref, timeout)
        result
      :noconnect ->
        :noconnect
    end
  end

  defp begin(ref, mode, depth, queue_time, log?, timeout, opts) do
    case Poolboy.connection(ref) do
      {:ok, {mod, conn}} ->
        sql = begin_sql(mod, mode, depth)
        query(ref, mod, conn, queue_time, sql, [], log?, timeout, opts)
      {:error, :noconnect} ->
        :noconnect
    end
  end

  defp begin_sql(mod, :raw, 0), do: mod.begin_transaction
  defp begin_sql(mod, :raw, :sandbox), do: mod.savepoint "ecto_sandbox"
  defp begin_sql(mod, _, depth), do: mod.savepoint "ecto_#{depth}"

  defp commit(ref, mode, depth, log?, timeout, opts, result) do
    case commit(ref, mode, depth, log?, timeout, opts) do
      {{:ok, _}, entry} ->
        {result, entry}
      {{:error, _err}, _entry} = error ->
        Poolboy.disconnect(ref, timeout)
        error
      :nocommit ->
        {result, nil}
      :noconnect ->
        {result, nil}
    end
  end

  defp commit(ref, :raw, 0, log?, timeout, opts) do
    case Poolboy.connection(ref) do
      {:ok, {mod, conn}} ->
        sql = mod.commit
        query(ref, mod, conn, nil, sql, [], log?, timeout, opts)
      {:error, :noconnect} ->
        :noconnect
    end
  end
  defp commit(_ref, _mode, _depth, _log?, _timeout, _opts) do
    :nocommit
  end

  defp rollback(ref, mode, depth, queue_time, log?, timeout, opts, result) do
    case rollback(ref, mode, depth, queue_time, log?, timeout, opts) do
      {{:ok, _}, entry} ->
        {result, entry}
      {{:error, _err}, _entry} = error ->
        Poolboy.disconnect(ref, timeout)
        error
      :noconnect ->
        {result, nil}
    end
  end

  defp rollback(ref, mode, depth, queue_time, log?, timeout, opts) do
    case Poolboy.connection(ref) do
      {:ok, {mod, conn}} ->
        sql = rollback_sql(mod, mode, depth)
        query(ref, mod, conn, queue_time, sql, [], log?, timeout, opts)
      {:error, :noconnect} ->
        :noconnect
    end
  end

  defp rollback_sql(mod, :raw, 0), do: mod.rollback
  defp rollback_sql(mod, :sandbox, :sandbox) do
    mod.rollback_to_savepoint "ecto_sandbox"
  end
  defp rollback_sql(mod, _, depth) do
    mod.rollback_to_savepoint "ecto_#{depth}"
  end
end
