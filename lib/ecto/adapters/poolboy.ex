defmodule Ecto.Adapters.Poolboy do
  @moduledoc """
  Start a pool of connections using `poolboy`.

  ### Options

    * `:size` - The number of connections to keep in the pool (default: 10)
    * `:lazy` - When true, connections to the repo are lazily started (default: true)
    * `:max_overflow` - The maximum overflow of connections (default: 0) (see poolboy docs)

  """

  alias Ecto.Adapters.Poolboy.Worker
  @behaviour Ecto.Adapters.Pool
  @behaviour Ecto.Adapters.Pool.Transaction

  @doc """
  Starts a pool of connections for the given connection module and options.

    * `conn_mod` - The connection module, see `Ecto.Adapters.Connection`
    * `opts` - The options for the pool and the connections

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

  @doc false
  def open_transaction(pool, timeout) do
    case :timer.tc(fn() -> checkout(pool, timeout) end) do
      {queue_time, {mode, worker, mod_conn}} ->
        {mode, {worker, mod_conn}, queue_time}
      {_, {:error, :noproc} = error} ->
        error
    end
  end

  @doc false
  def transaction_mode(_, {worker, _}, mode, timeout) do
    Worker.transaction_mode(worker, mode, timeout)
  end

  @doc false
  def transaction_connection(_, {_, mod_conn}, _) do
    {:ok, mod_conn}
  end

  @doc false
  def close_transaction(pool, {worker, _}, timeout) do
    try do
      Worker.close_transaction(worker, timeout)
    after
      :poolboy.checkin(pool, worker)
    end
  end

  @doc false
  def disconnect_transaction(pool, {worker, _}, timeout) do
    try do
      Worker.disconnect_transaction(worker, timeout)
    after
      :poolboy.checkin(pool, worker)
    end
  end

  ## Helpers

  defp split_opts(opts) do
    {pool_opts, conn_opts} = Keyword.split(opts, [:name, :size, :max_overflow])

    {pool_name, pool_opts} = Keyword.pop(pool_opts, :name)

    pool_opts = pool_opts
      |> Keyword.put_new(:size, 10)
      |> Keyword.put_new(:max_overflow, 0)

    pool_opts = [worker_module: Worker] ++ pool_opts

    unless is_nil(pool_name) do
      pool_opts = [name: {:local, pool_name}] ++ pool_opts
    end

    {pool_opts, conn_opts}
  end

  defp checkout(pool, timeout) do
    try do
      :poolboy.checkout(pool, :true, timeout)
    catch
      :exit, {:noproc, _} ->
        {:error, :noproc}
    else
      worker ->
        open_transaction(pool, worker, timeout)
    end
  end

  defp open_transaction(pool, worker, timeout) do
    try do
      Worker.open_transaction(worker, timeout)
    catch
      class, reason ->
        stack = System.stacktrace()
        :poolboy.checkin(pool, worker)
        :erlang.raise(class, reason, stack)
    else
      {mode, {_, _} = mod_conn} when mode in [:raw, :sandbox] ->
        {mode, worker, mod_conn}
      {:error, err} ->
        :poolboy.checkin(pool, worker)
        raise err
    end
  end

end
