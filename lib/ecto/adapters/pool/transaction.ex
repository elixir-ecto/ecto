defmodule Ecto.Adapters.Pool.Transaction do
  @moduledoc """
  Behaviour and implementation for carrying out nested transactions using a
  connection from a pool.
  """

  use Behaviour
  alias Ecto.Adapters.Pool

  @typedoc """
  Opaque transaction reference.

  Use inside `transaction/4` to retrieve the connection term or to disconnect
  the transaction, closing the connection.
  """
  @opaque ref :: {__MODULE__, module, Pool.t}

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
  Checkout a connection from a pool and open a transaction.

  Returns `{mode, conn, queue_time}` on success, where `conn` is any connection
  data associated with the transaction. The connection data can be retrieved
  inside a `transaction/4` with `connection/2`.

  Returns `{:error, :noproc}` if the pool is not alive and
  `{:error, :noconnect}` if a connection is not available.
  """
  defcallback open_transaction(Pool.t, timeout) ::
    {mode, conn, queue_time} | {:error, :noproc | :noconnect} when conn: any

  @doc """
  Get the connection module and process from the connection data for the current
  transaction.
  """
  defcallback transaction_connection(Pool.t, conn, timeout) ::
    {:ok, {module, pid}} | {:error, :noconnect} when conn: any

  @doc """
  Sets the mode of transaction to `mode`.
  """
  defcallback transaction_mode(Pool.t, conn, mode, timeout) ::
    :ok | {:error, :noconnect} when conn: any

  @doc """
  Closes the transaction and returns the connection back into the pool.

  Called once the transaction at `depth` `1` is finished, if the transaction
  is not broken with `disconnect/2`.
  """
  defcallback close_transaction(Pool.t, conn, timeout) :: :ok when conn: any

  @doc """
  Disconnects the connection for the current transaction.

  Called when the transaction has failed and the connection should be closed.
  However when in `:sandbox` mode the connection is not closed but the
  transaction can no longer access the connection.
  """
  defcallback disconnect_transaction(Pool.t, conn, timeout) :: :ok when conn: any

  @doc """
  Carry out a transaction using a pool.

  A transaction returns the value returned by the function wrapped in a tuple
  as `{:ok, value}`. Transactions can be nested and the `depth` shows the depth
  of nested transaction for the module/pool combination.

  Returns `{:error, :noproc}` if the pool is not alive or `{:error, :noconnect}`
  if no connection is available.

  ## Examples

      Transaction.transaction(mod, pool, timeout,
        fn(ref, :sandbox, 1, _queue_time) -> :sandboxed_transaction end)

      Transaction.transaction(mod, pool, timeout,
        fn(ref, :raw, 1, _queue_time) ->
          {:ok, :nested} =
            Transaction.transaction(mod, pool, timeout, fn(ref, :raw, 1, nil) ->
              :nested
            end)
        end)

      Transaction.transaction(mod, :pool1, timeout,
        fn(ref, :raw, 1, _queue_time1) ->
          {:ok, :different_pool} =
            Transaction.transaction(mod, :pool2, timeout,
              fn(ref, :raw, 1, _queue_time2) -> :different_pool end)
        end)

  """
  @spec transaction(module, Transaction.t, timeout,
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

      Transaction.transaction(mod, pool, timeout,
        fn(ref, :raw, 1, _queue_time) ->
          :ok = Transaction.mode(ref, :sandbox, timeout)
          Transaction.transaction(mod, pool, timeout,
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

      Transaction.transaction(mod, pool, timeout,
        fn(ref, :raw, 1, _queue_time) ->
          {:ok, {mod, conn}} = Transaction.connection(ref, timeout)
        end)

  """
  @spec connection(ref, timeout) ::
    {:ok, conn} | {:error, :noconnect} when conn: any
  def connection(ref, timeout) do
    case Process.get(ref) do
      %{conn: _} = info ->
        connection(ref, info, timeout)
      %{} ->
        {:error, :noconnect}
    end
  end

  @doc """
  Disconnect the connection for the active transaction.

  Calling `connection/1` inside the same transaction (at any depth) will
  return `{:error, :noconnect}`.

  ## Examples

      Transaction.transaction(mod, pool, timout,
        fn(ref, :raw, 1, _queue_time) ->
          {:ok, {mod, conn}} = Transaction.connection(ref, timeout)
          :ok = Transaction.disconnect(ref, timeout)
          {:error, :noconnect} = Transaction.connection(ref, timeout)
        end)

      Transaction.transaction(mod, pool, timeout,
        fn(ref, :raw, 1, _queue_time) ->
          :ok = Transaction.disconnect(ref, timeout)
          {:error, :noconnect} =
            Transaction.transaction(mod, pool, timeout, fn(_, _, _, _) -> end)
        end)

  """
  @spec disconnect(ref, timeout) :: :ok
  def disconnect({__MODULE__, pool_mod, pool} = ref, timeout) do
    case Process.get(ref) do
      %{conn: conn} = info ->
        _ = Process.put(ref, Map.delete(info, :conn))
        pool_mod.disconnect_transaction(pool, conn, timeout)
      %{} ->
        :ok
    end
  end

  @doc """
  Apply a function inside a transaction and disconnect the connection if the
  function raises.

  ## Examples

      Transaction.transaction(mod, pool, timeout,
        fn(ref, :raw, 1, _queue_time) ->
          try do
            Transaction.fuse(ref, timeout, fn() -> "oops" end)
          rescue
            RuntimeError ->
              {:error, :noconnect} = Transaction.connection(ref, timeout)
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
      {mode, conn, time} when mode in [:raw, :sandbox] ->
        # We got permission to start a transaction
        {:ok, %{conn: conn, depth: 0, mode: mode}, time}
      {:error, reason} = error when reason in [:noproc, :noconnect] ->
        error
      {:error, err} ->
        raise err
    end
  end

  defp close_transaction(pool_mod, pool, %{conn: conn}, timeout) do
    pool_mod.close_transaction(pool, conn, timeout)
  end
  defp close_transaction(_, _, %{}, _) do
    :ok
  end

  defp mode({__MODULE__, pool_mod, pool} = ref, %{conn: conn} = info,
  mode, timeout) do
    put_mode = fn() -> pool_mod.transaction_mode(pool, conn, mode, timeout) end
    case fuse(ref, timeout, put_mode) do
      :ok ->
        _ = Process.put(ref, %{info | mode: mode})
        :ok
      {:error, :noconnect} = error ->
        _ = Process.put(ref, Map.delete(info, :conn))
        error
    end
  end

  defp connection({__MODULE__, pool_mod, pool} = ref, %{conn: conn} = info,
  timeout) do
    get_conn = fn() -> pool_mod.transaction_connection(pool, conn, timeout) end
    case fuse(ref, timeout, get_conn) do
      {:ok, {_, _}} = ok ->
        ok
      {:error, :noconnect} = error ->
        _ = Process.put(ref, Map.delete(info, :conn))
        error
    end
  end
end
