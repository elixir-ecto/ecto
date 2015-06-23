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
  Opaque transaction reference.

  Use inside `transaction/4` to retrieve the connection term or to disconnect
  the transaction, closing the connection.
  """
  @opaque ref :: {__MODULE__, module, t}

  @typedoc """
  The mode of a transaction.

  Supported modes:

    * `:raw` - direct transaction without a sandbox
    * `:sandbox` - transaction inside a sandbox
  """
  @type mode :: :raw | :sandbox

  @typedoc """
  The depth of nested transactions.
  """
  @type depth :: pos_integer

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
  Checkout a connection from a pool and open a transaction.

  Returns `{mode, worker, conn, queue_time}` on success, where `worker` is the
  worker term and conn is a 2-tuple contain the connection's module and
  pid. The `conn` tuple can be retrieved inside a `transaction/4` with
  `connection/2`.

  Returns `{:error, :noproc}` if the pool is not alive and
  `{:error, :noconnect}` if a connection is not available.
  """
  defcallback open_transaction(t, timeout) ::
    {mode, worker, conn, queue_time} |
    {:error, :noproc | :noconnect} when worker: any, conn: {module, pid}

  @doc """
  Sets the mode of transaction to `mode`.
  """
  defcallback transaction_mode(t, worker, mode, timeout) ::
    :ok | {:error, :noconnect} when worker: any

  @doc """
  Closes the transaction and returns the connection back into the pool.

  Called once the transaction at `depth` `1` is finished, if the transaction
  is not broken with `disconnect/2`.
  """
  defcallback close_transaction(t, worker, timeout) :: :ok when worker: any

  @doc """
  Disconnects the connection for the current transaction.

  Called when the transaction has failed and the connection should be closed.
  However when in `:sandbox` mode the connection is not closed but the
  transaction can no longer access the connection.
  """
  defcallback disconnect_transaction(t, worker, timeout) :: :ok when worker: any

  @doc """
  Carry out a transaction using a pool.

  A transaction returns the value returned by the function wrapped in a tuple
  as `{:ok, value}`. Transactions can be nested and the `depth` shows the depth
  of nested transaction for the module/pool combination.

  Returns `{:error, :noproc}` if the pool is not alive or `{:error, :noconnect}`
  if no connection is available.

  ## Examples

      Pool.transaction(mod, pool, timeout,
        fn(ref, :sandbox, 1, _queue_time) -> :sandboxed_transaction end)

      Pool.transaction(mod, pool, timeout,
        fn(ref, :raw, 1, _queue_time) ->
          {:ok, :nested} =
            Pool.transaction(mod, pool, timeout, fn(ref, :raw, 1, nil) ->
              :nested
            end)
        end)

      Pool.transaction(mod, :pool1, timeout,
        fn(ref, :raw, 1, _queue_time1) ->
          {:ok, :different_pool} =
            Pool.transaction(mod, :pool2, timeout,
              fn(ref, :raw, 1, _queue_time2) -> :different_pool end)
        end)

  """
  @spec transaction(module, t, timeout,
  ((ref, mode, depth, queue_time | nil) -> result)) ::
    {:ok, result} | {:error, :noproc | :noconnect} when result: var
  def transaction(pool_mod, pool, timeout, fun) do
    ref = {__MODULE__, pool_mod, pool}
    case Process.get(ref) do
      nil ->
        transaction(pool_mod, pool, ref, timeout, fun)
      %{conn: _} = info ->
        do_transaction(ref, info, nil, fun)
      %{} ->
        {:error, :noconnect}
    end
  end

  @doc """
  Set the mode for the active transaction.

  ## Examples

      Pool.transaction(mod, pool, timeout,
        fn(ref, :raw, 1, _queue_time) ->
          :ok = Pool.mode(ref, :sandbox, timeout)
          Pool.transaction(mod, pool, timeout,
            fn(ref, :sandbox, 1, nil) -> :sandboxed end)
        end)

  """
  @spec mode(ref, mode, timeout) ::
    :ok | {:error, :already_mode | :noconnect}
  def mode({__MODULE__, _, _} = ref, mode, timeout) do
    case Process.get(ref) do
      %{conn: _ , mode: ^mode} ->
        {:error, :already_mode}
      %{conn: _} = info ->
        mode(ref, info, mode, timeout)
      %{} ->
        {:error, :noconnect}
    end
  end

  @doc """
  Get the connection module and pid for the active transaction.

  ## Examples

      Pool.transaction(mod, pool, timeout,
        fn(ref, :raw, 1, _queue_time) ->
          {:ok, {mod, conn}} = Pool.connection(ref)
        end)

  """
  @spec connection(ref) ::
    {:ok, conn} | {:error, :noconnect} when conn: {module, pid}
  def connection(ref) do
    case Process.get(ref) do
      %{conn: conn} ->
        {:ok, conn}
      %{} ->
        {:error, :noconnect}
    end
  end

  @doc """
  Disconnect the connection for the active transaction.

  Calling `connection/1` inside the same transaction (at any depth) will
  return `{:error, :noconnect}`.

  ## Examples

      Pool.transaction(mod, pool, timout,
        fn(ref, :raw, 1, _queue_time) ->
          {:ok, {mod, conn}} = Pool.connection(ref)
          :ok = Pool.disconnect(ref, timeout)
          {:error, :noconnect} = Pool.connection(ref)
        end)

      Pool.transaction(mod, pool, timeout,
        fn(ref, :raw, 1, _queue_time) ->
          :ok = Pool.disconnect(ref, timeout)
          {:error, :noconnect} =
            Pool.transaction(mod, pool, timeout, fn(_, _, _, _) -> end)
        end)

  """
  @spec disconnect(ref, timeout) :: :ok
  def disconnect({__MODULE__, pool_mod, pool} = ref, timeout) do
    case Process.get(ref) do
      %{conn: _, worker: worker} = info ->
        _ = Process.put(ref, Map.delete(info, :conn))
        pool_mod.disconnect_transaction(pool, worker, timeout)
      %{} ->
        :ok
    end
  end

  @doc """
  Apply a function inside a transaction and disconnect the connection if the
  function raises.

  ## Examples

      Pool.transaction(mod, pool, timeout,
        fn(ref, :raw, 1, _queue_time) ->
          try do
            Pool.fuse(ref, timeout, fn() -> "oops" end)
          rescue
            RuntimeError ->
              {:error, :noconnect} = Pool.connection(ref)
          end
        end)

  """
  def fuse(ref, timeout, fun) do
    try do
      fun.()
    catch
      class, reason ->
        stack = System.stacktrace()
        disconnect(ref, timeout)
        :erlang.raise(class, reason, stack)
    end
  end

  ## Helpers

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

  defp do_transaction(ref, %{depth: depth, mode: mode} = info, time, fun) do
    depth = depth + 1
    _ = Process.put(ref, %{info | depth: depth})
    try do
      {:ok, fun.(ref, mode, depth, time)}
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
      {mode, worker, conn, time} when mode in [:raw, :sandbox] ->
        # We got permission to start a transaction
        {:ok, %{worker: worker, conn: conn, depth: 0, mode: mode}, time}
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

  defp mode({__MODULE__, pool_mod, pool} = ref, %{worker: worker} = info,
  mode, timeout) do
    put_mode = fn() -> pool_mod.transaction_mode(pool, worker, mode, timeout) end
    case fuse(ref, timeout, put_mode) do
      :ok ->
        _ = Process.put(ref, %{info | mode: mode})
        :ok
      {:error, :noconnect} = error ->
        _ = Process.put(ref, Map.delete(info, :conn))
        error
    end
  end
end
