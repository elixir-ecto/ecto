defmodule Ecto.Pools.Poolboy do
  @moduledoc """
  Start a pool of connections using `poolboy`.

  ### Options

    * `:pool_name` - The name of the pool supervisor
    * `:pool_size` - The number of connections to keep in the pool (default: 10)
    * `:lazy` - When true, connections to the repo are lazily started (default: true)
    * `:max_overflow` - The maximum overflow of connections (default: 0) (see poolboy docs)
    * `:shutdown` - The shutdown method for the connections (default: 5000) (see Supervisor.Spec)

  """

  alias Ecto.Pools.Poolboy.Worker
  @behaviour Ecto.Pool

  @doc """
  Starts a pool of connections for the given connection module and options.

    * `conn_mod` - The connection module, see `Ecto.Adapters.Connection`
    * `opts` - The options for the pool and the connections

  """
  def start_link(conn_mod, opts) do
    {:ok, _} = Application.ensure_all_started(:poolboy)
    {pool_opts, conn_opts} = split_opts(opts)
    :poolboy.start_link(pool_opts, {conn_mod, conn_opts})
  end

  @doc false
  def checkout(pool, timeout) do
    checkout(pool, :run, timeout)
  end

  @doc false
  def checkin(pool, worker, _) do
    :poolboy.checkin(pool, worker)
  end

  @doc false
  def open_transaction(pool, timeout) do
    checkout(pool, :transaction, timeout)
  end

  @doc false
  def close_transaction(pool, worker, _) do
    try do
      Worker.checkin(worker)
    after
      :poolboy.checkin(pool, worker)
    end
  end

  @doc false
  def break(pool, worker, timeout) do
    try do
      Worker.break(worker, timeout)
    after
      :poolboy.checkin(pool, worker)
    end
  end

  ## Helpers

  defp split_opts(opts) do
    {pool_opts, conn_opts} = Keyword.split(opts, [:pool_name, :pool_size, :max_overflow])

    conn_opts =
      conn_opts
      |> Keyword.put(:timeout, Keyword.get(opts, :connect_timeout, 5_000))

    pool_opts = [worker_module: Worker,
                 name: {:local, Keyword.fetch!(pool_opts, :pool_name)},
                 size: Keyword.get(pool_opts, :pool_size, 10),
                 max_overflow: Keyword.get(pool_opts, :max_overflow, 0)]

    {pool_opts, conn_opts}
  end

  defp checkout(pool, fun, timeout) do
    case :timer.tc(fn() -> do_checkout(pool, fun, timeout) end) do
      {queue_time, {:ok, worker, mod_conn}} ->
        {:ok, worker, mod_conn, queue_time}
      {_queue_time, {:error, _} = error} ->
        error
    end
  end

  defp do_checkout(pool, fun, timeout) do
    try do
      :poolboy.checkout(pool, :true, timeout)
    catch
      :exit, {:noproc, _} ->
        {:error, :noproc}
    else
      worker ->
        do_checkout(pool, worker, fun, timeout)
    end
  end

  defp do_checkout(pool, worker, fun, timeout) do
    try do
      Worker.checkout(worker, fun, timeout)
    catch
      class, reason ->
        stack = System.stacktrace()
        :poolboy.checkin(pool, worker)
        :erlang.raise(class, reason, stack)
    else
      {:ok, mod_conn} ->
        {:ok, worker, mod_conn}
      {:error, err} ->
        :poolboy.checkin(pool, worker)
        raise err
    end
  end
end
