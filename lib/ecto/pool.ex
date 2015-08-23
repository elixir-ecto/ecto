defmodule Ecto.Pool do
  @moduledoc """
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
    * `:pool_size` - The number of connections to keep in the pool

  Returns `{:ok, pid}` on starting the pool.

  Returns `{:error, reason}` if the pool could not be started. If the `reason`
  is  {:already_started, pid}}` a pool with the same name has already been
  started.
  """
  defcallback start_link(module, opts) ::
    {:ok, pid} | {:error, any} when opts: Keyword.t

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

  Returns `{:error, :noproc}` if the pool is not alive or
  `{:error, :noconnect}` if no connection is available.

  ## Examples

      Pool.run(mod, pool, timeout,
        fn(_conn, queue_time) -> queue_time end)

      Pool.transaction(mod, pool, timeout,
        fn(:opened, _ref, _conn, _queue_time) ->
          {:ok, :nested} =
            Pool.run(mod, pool, timeout, fn(_conn, nil) ->
              :nested
            end)
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
      %{conn: conn, tainted: false} ->
        {:ok, fun.(conn, nil)}
      %{} ->
        {:error, :noconnect}
    end
  end

  defp do_run(pool_mod, pool, timeout, fun) do
    case checkout(pool_mod, pool, timeout) do
      {:ok, worker, conn, time} ->
        try do
          {:ok, fun.(conn, time)}
        after
          pool_mod.checkin(pool, worker, timeout)
        end
      {:error, _} = error ->
        error
    end
  end

  defp checkout(pool_mod, pool, timeout) do
    case pool_mod.checkout(pool, timeout) do
      {:ok, _worker, _conn, _time} = ok ->
        ok
      {:error, reason} = error when reason in [:noproc, :noconnect] ->
        error
      {:error, err} ->
        raise err
    end
  end

  @doc """
  Carries out a transaction using a connection from a pool.

  Once a transaction is opened, all following calls to `run/4` or
  `transaction/4` will use the same connection/worker. If `break/2` is invoked,
  all operations will return `{:error, :noconnect}` until the end of the
  top level transaction.

  Nested calls to pool transaction will "flatten out" transactions. This means
  nested calls are mostly no-op and just execute the given function passing
  `:already_opened` as first argument. If there is any failure in a nested
  transaction, the whole transaction is marked as tainted, ensuring the outer
  most call fails.

  Returns `{:error, :noproc}` if the pool is not alive, `{:error, :noconnect}`
  if no connection is available. Otherwise just returns the given function value
  without wrapping.

  ## Examples

      Pool.transaction(mod, pool, timeout,
        fn(:opened, _ref, _conn, queue_time) -> queue_time end)

      Pool.transaction(mod, pool, timeout,
        fn(:opened, ref, _conn, _queue_time) ->
          :nested =
            Pool.transaction(mod, pool, timeout, fn(:already_opened, _ref, _conn, nil) ->
              :nested
            end)
        end)

      Pool.transaction(mod, :pool1, timeout,
        fn(:opened, _ref1, _conn1, _queue_time1) ->
          :different_pool =
            Pool.transaction(mod, :pool2, timeout,
              fn(:opened, _ref2, _conn2, _queue_time2) -> :different_pool end)
        end)

  """
  @spec transaction(module, t, timeout, fun) ::
        value | {:error, :noproc} | {:error, :noconnect} | no_return
        when fun: (:opened | :already_open, ref, conn, queue_time | nil -> value),
             conn: {module, pid},
             value: var
  def transaction(pool_mod, pool, timeout, fun) do
    ref = {__MODULE__, pool_mod, pool}
    case Process.get(ref) do
      nil ->
        case pool_mod.open_transaction(pool, timeout) do
          {:ok, worker, conn, time} ->
            outer_transaction(ref, worker, conn, time, timeout, fun)
          {:error, reason} = error when reason in [:noproc, :noconnect] ->
            error
          {:error, err} ->
            raise err
        end
      %{conn: conn} ->
        inner_transaction(ref, conn, fun)
    end
  end

  defp outer_transaction(ref, worker, conn, time, timeout, fun) do
    Process.put(ref, %{worker: worker, conn: conn, tainted: false})

    try do
      fun.(:opened, ref, conn, time)
    catch
      # If any error leaked, it should be a bug in Ecto.
      kind, reason ->
        stack = System.stacktrace()
        break(ref, timeout)
        :erlang.raise(kind, reason, stack)
    else
      res ->
        close_transaction(ref, Process.get(ref), timeout)
        res
    after
      Process.delete(ref)
    end
  end

  defp inner_transaction(ref, conn, fun) do
    try do
      fun.(:already_open, ref, conn, nil)
    catch
      kind, reason ->
        stack = System.stacktrace()
        tainted(ref, true)
        :erlang.raise(kind, reason, stack)
    end
  end

  defp close_transaction({__MODULE__, pool_mod, pool}, %{conn: _, worker: worker}, timeout) do
    pool_mod.close_transaction(pool, worker, timeout)
    :ok
  end

  defp close_transaction(_, %{}, _) do
    :ok
  end

  @doc """
  Executes the given function giving it the ability to rollback.

  Returns `{:ok, value}` if no transaction ocurred,
  `{:error, value}` if the user rolled back or
  `{:raise, kind, error, stack}` in case there was a failure.
  """
  @spec with_rollback(:opened | :already_open, ref, (() -> return)) ::
        {:ok, return} | {:error, term} | {:raise, atom, term, Exception.stacktrace}
        when return: var
  def with_rollback(:opened, ref, fun) do
    try do
      value = fun.()
      case Process.get(ref) do
        %{tainted: true}  -> {:error, :rollback}
        %{tainted: false} -> {:ok, value}
      end
    catch
      :throw, {:ecto_rollback, ^ref, value} ->
        {:error, value}
      kind, reason ->
        stack = System.stacktrace()
        {:raise, kind, reason, stack}
    after
      tainted(ref, false)
    end
  end

  def with_rollback(:already_open, ref, fun) do
    try do
      {:ok, fun.()}
    catch
      :throw, {:ecto_rollback, ^ref, value} ->
        tainted(ref, true)
        {:error, value}
    end
  end

  @doc """
  Triggers a rollback that is handled by `with_rollback/2`.

  Raises if outside a transaction.
  """
  def rollback(pool_mod, pool, value) do
    ref = {__MODULE__, pool_mod, pool}
    if Process.get(ref) do
      throw {:ecto_rollback, ref, value}
    else
      raise "cannot call rollback outside of transaction"
    end
  end

  defp tainted(ref, bool) do
    map = Process.get(ref)
    Process.put(ref, %{map | tainted: bool})
    :ok
  end

  @doc """
  Breaks the active connection.

  Any attempt to use it inside the same transaction
  Calling `run/1` inside the same transaction or run (at any depth) will
  return `{:error, :noconnect}`.

  ## Examples

      Pool.transaction(mod, pool, timout,
        fn(:opened, ref, conn, _queue_time) ->
          :ok = Pool.break(ref, timeout)
          {:error, :noconnect} = Pool.run(mod, pool, timeout, fn _, _ -> end)
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
end
