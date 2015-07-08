defmodule Ecto.Pools.SojournBroker do
  @moduledoc """
  Start a pool of connections using `sbroker`.

  ### Options

    * `:size` - The number of connections to keep in the pool (default: 10)
    * `:min_backoff` - The minimum backoff on failed connect in milliseconds (default: 50)
    * `:max_backoff` - The maximum backoff on failed connect in milliseconds (default: 5000)
    * `:broker` - The `sbroker` module to use (default: `Ecto.Pools.SojournBroker.Timeout`)
    * `:lazy` - When true, initial connections to the repo are lazily started (default: true)
    * `:shutdown` - The shutdown method for the connections (default: 5000) (see Supervisor.Spec)

  """

  alias Ecto.Pools.SojournBroker.Worker
  @behaviour Ecto.Pool

  @doc """
  Starts a pool of connections for the given connection module and options.

    * `conn_mod` - The connection module, see `Ecto.Adapters.Connection`
    * `opts` - The options for the pool, the broker and the connections

  """
  def start_link(conn_mod, opts) do
    {:ok, _} = Application.ensure_all_started(:sbroker)
    {pool_opts, opts} = split_opts(opts)

    import Supervisor.Spec
    name = Keyword.fetch!(pool_opts, :name)
    mod  = Keyword.fetch!(pool_opts, :broker)
    args = [{:local, name}, mod, opts, [time_unit: :micro_seconds]]
    broker = worker(:sbroker, args)

    size = Keyword.fetch!(pool_opts, :size)
    workers = for id <- 1..size do
      worker(Worker, [conn_mod, opts], [id: id])
    end
    worker_sup_opts = [strategy: :one_for_one, max_restarts: size]
    worker_sup = supervisor(Supervisor, [workers, worker_sup_opts])

    children = [broker, worker_sup]
    sup_opts = [strategy: :rest_for_one, name: Module.concat(name, Supervisor)]
    Supervisor.start_link(children, sup_opts)
  end

  @doc false
  def checkout(pool, timeout) do
    ask(pool, :run, timeout)
  end

  @doc false
  def checkin(_, {worker, ref}, _) do
    Worker.done(worker, ref)
  end

  @doc false
  def open_transaction(pool, timeout) do
    ask(pool, :transaction, timeout)
  end

  @doc false
  def close_transaction(_, {worker, ref}, _) do
    Worker.done(worker, ref)
  end

  @doc false
  def break(_, {worker, ref}, timeout) do
    Worker.break(worker, ref, timeout)
  end

  ## Helpers

  defp ask(pool, fun, timeout) do
    case :sbroker.ask(pool, {fun, self()}) do
      {:go, ref, {worker, :lazy}, _, queue_time} ->
          lazy_connect(worker, ref, queue_time, timeout)
      {:go, ref, {worker, mod_conn}, _, queue_time} ->
          {:ok, {worker, ref}, mod_conn, queue_time}
      {:drop, _} ->
        {:error, :noconnect}
    end
  end

  ## Helpers

  defp split_opts(opts) do
    {pool_opts, opts} = Keyword.split(opts, [:size, :broker])

    opts = opts
      |> Keyword.put_new(:queue_timeout, Keyword.get(opts, :timeout, 5_000))
      |> Keyword.put(:timeout, Keyword.get(opts, :connect_timeout, 5_000))

    pool_opts = pool_opts
      |> Keyword.put_new(:size, 10)
      |> Keyword.put_new(:broker, Ecto.Pools.SojournBroker.Timeout)
      |> Keyword.put(:name, Keyword.fetch!(opts, :name))

    {pool_opts, opts}
  end

  defp lazy_connect(worker, ref, queue_time, timeout) do
    try do
      :timer.tc(Worker, :mod_conn, [worker, ref, timeout])
    catch
      class, reason ->
        stack = System.stacktrace()
        Worker.done(worker, ref)
        :erlang.raise(class, reason, stack)
    else
      {connect_time, {:ok, mod_conn}} ->
        {:ok, {worker, ref}, mod_conn, queue_time + connect_time}
      {_, {:error, :noconnect} = error} ->
        Worker.done(worker, ref)
        error
    end
  end
end
