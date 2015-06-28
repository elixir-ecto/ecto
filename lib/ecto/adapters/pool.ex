defmodule Ecto.Adapters.Pool do
  @modueldoc"""
  Behaviour for using a pool of connections.
  """

  use Behaviour

  @typedoc """
  A pool process
  """
  @type t :: atom | pid

  @typedoc """
  Opaque connection reference.

  Use inside `run/4` and `transaction/4` to retrieve the connection module and
  pid or break the transaction.
  """
  @opaque ref :: {__MODULE__, module, t}

  @typedoc """
  The depth of nested transactions.
  """
  @type depth :: non_neg_integer

  @typedoc """
  The time in microseconds spent waiting for a connection from the pool.
  """
  @type queue_time :: non_neg_integer

  @doc """
  Start a pool of connections.

  `module` is the connection module, which should define the
  `Ecto.Adapters.Connection` callbacks, and `opts` are its (and the pool's)
  options.

  A pool should support the following options:

    * `:name` - The name of the pool
    * `:size` - The number of connections to keep in the pool

  Returns `{:ok, pid}` on starting the pool.

  Returns `{:error, reason}` if the pool could not be started. If the `reason`
  is  {:already_started, pid}}` a pool with the same name has already been
  started.
  """
  defcallback start_link(module, opts) ::
    {:ok, pid} | {:error, any} when opts: Keyword.t

  @doc """
  Stop a pool.
  """
  defcallback stop(t) :: :ok

  @doc """
  Checkout a worker/connection from the pool.

  The connection should not be closed if the calling process exits without
  returning the connection.

  Returns `{:ok, worker, conn, queue_time}` on success, where `worker` is the
  worker term and conn is a 2-tuple contain the connection's module and
  pid. The `conn` tuple can be retrieved inside a `transaction/4` with
  `connection/1`.

  Returns `{:error, :noproc}` if the pool is not alive and
  `{:error, :noconnect}` if a connection is not available.
  """
  defcallback checkout(t, timeout) ::
    {:ok, worker, conn, queue_time} |
    {:error, :noproc | :noconnect} when worker: any, conn: {module, pid}

  @doc """
  Checkin a worker/connection to the pool.

  Called when the top level `run/4` finishes, if `break/2` was not called
  inside the fun.
  """
  defcallback checkin(t, worker, timeout) :: :ok when worker: any

  @doc """
  Break the current transaction or run.

  Called when the function has failed and the connection should no longer be
  available to to the calling process.
  """
  defcallback break(t, worker, timeout) :: :ok when worker: any

  @doc """
  Open a transaction with a connection from the pool.

  The connection should be closed if the calling process exits without
  returning the connection.

  Returns `{:ok, worker, conn, queue_time}` on success, where `worker` is the
  worker term and conn is a 2-tuple contain the connection's module and
  pid. The `conn` tuple can be retrieved inside a `transaction/4` with
  `connection/2`.

  Returns `{:error, :noproc}` if the pool is not alive and
  `{:error, :noconnect}` if a connection is not available.
  """
  defcallback open_transaction(t, timeout) ::
    {:ok, worker, conn, queue_time} |
    {:error, :noproc | :noconnect} when worker: any, conn: {module, pid}

  @doc """
  Close the transaction and signal to the worker the work with the connection
  is complete.

  Called once the transaction at `depth` `1` is finished, if the transaction
  is not broken with `break/2`.
  """
  defcallback close_transaction(t, worker, timeout) :: :ok when worker: any

  @doc """
  Runs a fun using a connection from a pool.

  The connection will be taken from the pool unless we are inside
  a `transaction/4` which, in this case, would already have a conn
  attached to it.

  Returns the value returned by the function wrapped in a tuple
  as `{:ok, value}`.

  Returns `{:error, :noproc}` if the pool is not alive or `{:error, :noconnect}`
  if no connection is available.

  ## Examples

      Pool.run(mod, pool, timeout,
        fn(_conn, queue_time) -> queue_time end)

      Pool.transaction(mod, pool, timeout,
        fn(_ref, _conn, 1, _queue_time) ->
          {:ok, :nested} =
            Pool.run(mod, pool, timeout, fn(_conn, nil) ->
              :nested
            end)
        end)

      Pool.run(mod, :pool1, timeout,
        fn(_conn1, _queue_time1) ->
          {:ok, :different_pool} =
            Pool.run(mod, :pool2, timeout,
              fn(_conn2, _queue_time2) -> :different_pool end)
        end)

  """
  @spec run(module, t, timeout, ((conn, queue_time | nil) -> result)) ::
        {:ok, result} | {:error, :noproc | :noconnect}
        when result: var, conn: {module, pid}
  def run(pool_mod, pool, timeout, fun) do
    ref = {__MODULE__, pool_mod, pool}
    case Process.get(ref) do
      nil ->
        do_run(pool_mod, pool, timeout, fun)
      %{conn: conn} ->
        {:ok, fuse(ref, timeout, fun, [conn, nil])}
      %{} ->
        {:error, :noconnect}
    end
  end

  @doc """
  Carry out a transaction using a connection from a pool.

  Once a transaction is opened, all following calls to `run/4` or
  `transaction/4` will use the same connection/worker. If `break/2` is invoked,
  all operations will return `{:error, :noconnect}` until the end of the
  top level transaction.

  A transaction returns the value returned by the function wrapped in a tuple
  as `{:ok, value}`. Transactions can be nested and the `depth` shows the depth
  of nested transaction for the module/pool combination.

  Returns `{:error, :noproc}` if the pool is not alive, `{:error, :noconnect}`
  if no connection is available or `{:error, :notransaction}` if called inside
  a `run/4` fun at depth `0`.

  ## Examples

      Pool.transaction(mod, pool, timeout,
        fn(_ref, _conn, 1, queue_time) -> queue_time end)

      Pool.transaction(mod, pool, timeout,
        fn(ref, _conn, 1, _queue_time) ->
          {:ok, :nested} =
            Pool.transaction(mod, pool, timeout, fn(_ref, _conn, 2, nil) ->
              :nested
            end)
        end)

      Pool.transaction(mod, :pool1, timeout,
        fn(_ref1, _conn1, 1, _queue_time1) ->
          {:ok, :different_pool} =
            Pool.transaction(mod, :pool2, timeout,
              fn(_ref2, _conn2, 1, _queue_time2) -> :different_pool end)
        end)

      Pool.run(mod, pool, timeout,
        fn(_conn, _queue_time) ->
          {:error, :notransaction} =
            Pool.transaction(mod, pool, timeout, fn(_, _, _, _) -> end)
        end)

  """
  @spec transaction(module, t, timeout,
                    ((ref, conn, depth, queue_time | nil) -> result)) ::
        {:ok, result} | {:error, :noproc | :noconnect | :notransaction}
        when result: var, conn: {module, pid}
  def transaction(pool_mod, pool, timeout, fun) do
    ref = {__MODULE__, pool_mod, pool}
    case Process.get(ref) do
      nil ->
        transaction(pool_mod, pool, ref, timeout, fun)
      %{depth: 0} ->
        {:error, :notransaction}
      %{conn: _} = info ->
        do_transaction(ref, info, nil, fun)
      %{} ->
        {:error, :noconnect}
    end
  end

  @doc """
  Break the active transaction or run.

  Calling `connection/1` inside the same transaction or run (at any depth) will
  return `{:error, :noconnect}`.

  ## Examples

      Pool.transaction(mod, pool, timout,
        fn(ref, conn, 1, _queue_time) ->
          {:ok, {_mod, ^conn}} = Pool.connection(ref)
          :ok = Pool.break(ref, timeout)
          {:error, :noconnect} = Pool.connection(ref)
        end)

      Pool.transaction(mod, pool, timeout,
        fn(ref, _conn, 1, _queue_time) ->
          :ok = Pool.break(ref, timeout)
          {:error, :noconnect} =
            Pool.transaction(mod, pool, timeout, fn(_, _, _, _) -> end)
        end)

  """
  @spec break(ref, timeout) :: :ok
  def break({__MODULE__, pool_mod, pool} = ref, timeout) do
    case Process.get(ref) do
      %{conn: _, worker: worker} = info ->
        _ = Process.put(ref, Map.delete(info, :conn))
        pool_mod.break(pool, worker, timeout)
      %{} ->
        :ok
    end
  end

  ## Helpers

  defp fuse(ref, timeout, fun, args) do
    try do
      apply(fun, args)
    catch
      class, reason ->
        stack = System.stacktrace()
        break(ref, timeout)
        :erlang.raise(class, reason, stack)
    end
  end

  defp do_run(pool_mod, pool, timeout, fun) do
    case checkout(pool_mod, pool, timeout) do
      {:ok, %{conn: conn, worker: worker} = info, time} ->
        try do
          {:ok, fun.(conn, time)}
        catch
          class, reason ->
            stack = System.stacktrace()
            pool_mod.break(pool, worker, timeout)
            :erlang.raise(class, reason, stack)
        after
          checkin(pool_mod, pool, info, timeout)
        end
      {:error, _} = error ->
        error
    end
  end

  defp checkout(pool_mod, pool, timeout) do
    case pool_mod.checkout(pool, timeout) do
      {:ok, worker, conn, time} ->
        # We got permission to start a transaction
        {:ok, %{worker: worker, conn: conn, depth: 0}, time}
      {:error, reason} = error when reason in [:noproc, :noconnect] ->
        error
      {:error, err} ->
        raise err
    end
  end

  defp checkin(pool_mod, pool, %{conn: _, worker: worker}, timeout) do
    pool_mod.checkin(pool, worker, timeout)
  end
  defp checkin(_, _, %{}, _) do
    :ok
  end

  defp transaction(pool_mod, pool, ref, timeout, fun) do
    case open_transaction(pool_mod, pool, timeout) do
      {:ok, info, time} ->
        try do
          do_transaction(ref, info, time, fun)
        after
          info = Process.delete(ref)
          close_transaction(pool_mod, pool, info, timeout)
        end
      {:error, _} = error ->
        error
    end
  end

  defp do_transaction(ref, %{depth: depth, conn: conn} = info, time, fun) do
    depth = depth + 1
    _ = Process.put(ref, %{info | depth: depth})
    try do
      {:ok, fun.(ref, conn, depth, time)}
    after
      case Process.put(ref, info) do
        %{conn: _} ->
          :ok
        %{} ->
          _ = Process.put(ref, Map.delete(info, :conn))
          :ok
      end
    end
  end

  defp open_transaction(pool_mod, pool, timeout) do
    case pool_mod.open_transaction(pool, timeout) do
      {:ok, worker, conn, time} ->
        # We got permission to start a transaction
        {:ok, %{worker: worker, conn: conn, depth: 0}, time}
      {:error, reason} = error when reason in [:noproc, :noconnect] ->
        error
      {:error, err} ->
        raise err
    end
  end

  defp close_transaction(pool_mod, pool, %{conn: _, worker: worker}, timeout) do
    pool_mod.close_transaction(pool, worker, timeout)
  end
  defp close_transaction(_, _, %{}, _) do
    :ok
  end
end
