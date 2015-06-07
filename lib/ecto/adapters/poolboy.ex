defmodule Ecto.Adapters.Poolboy do

  alias Ecto.Adapters.Worker

  @opaque ref :: {:ecto_transaction_info, atom}
  @type mode :: :raw | :sandbox
  @doc """
  Starts pool of connections for the given connection module and options.
  """
  def start_link(conn_mod, opts) do
    {pool_opts, conn_opts} = split_opts(opts)
    :poolboy.start_link(pool_opts, {conn_mod, conn_opts})
  end

  @doc """
  Stop the pool.
  """
  def stop(pool) do
    :poolboy.stop(pool)
  end

  @doc """
  Carry out a transaction on a worker in the pool.
  """
  @spec transaction(atom, timeout,
  ((ref, mode, non_neg_integer, nil | non_neg_integer) -> result)) ::
    {:ok, result} | {:error, :noproc | :noconnect} when result: var
  def transaction(pool, timeout, fun) do
    ref = {:ecto_transaction_info, pool}
    case Process.get(ref) do
      nil ->
        transaction(pool, ref, timeout, fun)
      %{conn: conn} = info when is_pid(conn) ->
        do_transaction(ref, info, fun)
      %{conn: nil} ->
        {:error, :noconnect}
    end
  end

  @doc """
  Set the mode of connection for the active transaction.
  """
  @spec mode(ref, :raw | :sandbox, timeout) ::
    :ok | {:error, :already_mode  |:noconnect}
  def mode(ref, mode, timeout) do
    case Process.get(ref) do
      %{conn: conn, mode: ^mode} when is_pid(conn) ->
        {:error, :already_mode}
      %{conn: conn} = info when is_pid(conn) ->
        mode(ref, info, mode, timeout)
      %{conn: nil} ->
        {:error, :noconnect}
    end
  end

  @doc """
  Get the connection from the active transaction.
  """
  @spec connection(ref) :: {:ok, {module, pid}} | {:error, :noconnect}
  def connection(ref) do
    case Process.get(ref) do
      %{module: module, conn: conn} when is_pid(conn) ->
        {:ok, {module, conn}}
      %{conn: nil} ->
        {:error, :noconnect}
    end
  end

  @doc """
  Disconnect the connection for the active transaction.
  """
  @spec disconnect(ref, timeout) :: :ok
  def disconnect(ref, timeout) do
    case Process.get(ref) do
      %{conn: conn, worker: worker} = info when is_pid(conn) ->
        _ = Process.put(ref, %{info | conn: nil})
        _ = Worker.break_transaction(worker, timeout)
        :ok
      %{conn: nil} ->
        :ok
    end
  end

  ## Helpers

  defp split_opts(opts) do
    {pool_opts, conn_opts} = Keyword.split(opts, [:name, :size, :max_overflow])

    {pool_name, pool_opts} = Keyword.pop(pool_opts, :name)

    pool_opts = pool_opts
      |> Keyword.put_new(:size, 10)
      |> Keyword.put_new(:max_overflow, 0)

    pool_opts =
    [name: {:local, pool_name},
      worker_module: Worker] ++ pool_opts

    {pool_opts, conn_opts}
  end

  defp transaction(pool, ref, timeout, fun) do
    case checkout(pool, timeout) do
      {:ok, {time, worker}} ->
        try do
          do_transaction(ref, worker, time, timeout, fun)
        after
          :poolboy.checkin(pool, worker)
        end
      {:error, _} = error ->
        error
    end
  end

  defp do_transaction(ref, worker, time, timeout, fun) do
    %{mode: mode, depth: depth} = info = open_transaction(worker, timeout)
    _ = Process.put(ref, info)
    try do
      {:ok, fun.(ref, mode, depth, time)}
    after
      case Process.delete(ref) do
        %{conn: conn} when is_pid(conn) ->
          Worker.close_transaction(worker, timeout)
        %{conn: nil} ->
          :ok
      end
    end
  end

  defp do_transaction(ref, %{depth: depth, mode: mode} = info, fun) do
    depth = depth + 1
    _ = Process.put(ref, %{info | depth: depth})
    try do
      {:ok, fun.(ref, mode, depth, nil)}
    after
      case Process.put(ref, info) do
        %{conn: conn} when is_pid(conn) ->
          :ok
        %{conn: nil} ->
          _ = Process.put(ref, %{info | conn: nil})
          :ok
      end
    end
  end

  defp checkout(pool, timeout) when is_pid(pool) do
    {:ok, :timer.tc(:poolboy, :checkout, [pool, true, timeout])}
  end
  defp checkout(pool, timeout) do
    case Process.whereis(pool) do
      nil ->
        {:error, :noproc}
      pool ->
        checkout(pool, timeout)
    end
  end

  defp open_transaction(worker, timeout) do
    case Worker.open_transaction(worker, timeout) do
      {mode, {module, conn}} when mode in [:raw, :sandbox] ->
        # We got permission to start a transaction
        %{worker: worker, module: module, conn: conn, depth: 0, mode: mode}
      {:error, err} ->
        raise err
    end
  end

  defp mode(ref, %{worker: worker} = info, mode, timeout) do
    try do
      Worker.mode(worker, mode, timeout)
    catch
      class, reason ->
        stack = System.stacktrace()
        disconnect(ref, timeout)
        :erlang.raise(class, reason, stack)
    else
      :ok ->
        _ = Process.put(ref, %{info | mode: mode})
        :ok
      :noconnect ->
        _ = Process.put(ref, %{info | conn: nil})
        {:error, :noconnect}
    end
  end
end
