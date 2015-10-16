defmodule Ecto.Pools.Ownership do
  defmodule Strategy do
    use Behaviour
    alias Ecto.Pool

    defcallback ownership_checkout(module, pid) :: Pool.mode
    defcallback ownership_checkin(module, pid) :: Pool.mode
  end

  defmodule Server do
    use GenServer

    @timeout 5_000

    def start_link(pool, pool_name, ets) do
      GenServer.start_link(__MODULE__, {pool, pool_name, ets})
    end

    def init({module, pool, ets}) do
      Process.flag(:trap_exit, true)
      {:ok, %{module: module,
              pool: pool,
              ets: ets,
              owner: nil,
              ref: nil,
              checkout: nil,
              strategy: nil}}
    end

    def handle_call({:ownership_checkout, strategy, timeout}, {pid, _ref}, s) do
      case s.module.checkout(s.pool, timeout) do
        {:ok, worker, {module, conn}, :default, _queue_time} ->
          mode = if strategy,
                   do: strategy.ownership_checkout(module, conn),
                 else: :default

          checkout = {worker, {module, conn}, mode}

          s = monitor_owner(pid, s)
          s = %{s | strategy: strategy, checkout: checkout}
          {:reply, {:ok, checkout}, s}
        {:error, _} = error ->
          {:stop, :normal, error, s}
      end
    end

    def handle_call({:ownership_checkin, timeout}, _from, s) do
      checkin(timeout, s)
      {:stop, :normal, :ok, s}
    end

    def handle_info({:DOWN, ref, :process, pid, _reason}, %{ref: ref, owner: pid} = s) do
      checkin(@timeout, s)
      {:stop, :normal, s}
    end

    def terminate(_reason, s) do
      if s.owner do
        :ets.delete(s.ets, s.owner)
      end
    end

    defp checkin(timeout, s) do
      {worker, {module, conn}, _} = s.checkout
      if s.strategy, do: s.strategy.ownership_checkin(module, conn)
      s.module.checkin(s.pool, worker, timeout)
    end

    defp monitor_owner(owner, %{owner: nil, ref: nil} = s) do
      ref = Process.monitor(owner)
      %{s | owner: owner, ref: ref}
    end
  end

  defmodule ServerSup do
    use Supervisor

    def start_link(name, pool, pool_name, ets) do
      Supervisor.start_link(__MODULE__, {pool, pool_name, ets}, name: name)
    end

    def init({pool, pool_name, ets}) do
      children = [
        worker(Server, [pool, pool_name, ets], restart: :temporary)
      ]
      supervise(children, strategy: :simple_one_for_one)
    end

    def new_owner(name) do
      Supervisor.start_child(name, [])
    end
  end

  defmodule Sup do
    use Supervisor

    def start_link(connection, opts) do
      Supervisor.start_link(__MODULE__, {connection, opts})
    end

    def init({connection, opts}) do
      {pool, opts} = Keyword.pop(opts, :ownership_pool)
      name         = Keyword.fetch!(opts, :pool_name)
      pool_name    = Module.concat(name, Inner)
      pool_opts    = Keyword.put(opts, :pool_name, pool_name)
      sup_name     = Module.concat(name, Elixir.ServerSup)

      :ets.new(name, [:named_table, :public, read_concurrency: true])
      :ets.insert(name, {:metadata, sup_name, pool_name, pool})

      children = [
        supervisor(ServerSup, [sup_name, pool, pool_name, name]),
        supervisor(pool, [connection, pool_opts])
      ]
      supervise(children, strategy: :rest_for_one)
    end
  end

  @behaviour Ecto.Pool
  @timeout 5_000

  def start_link(connection, opts) do
    Sup.start_link(connection, opts)
  end

  def ownership_checkout(repo, strategy \\ nil, timeout \\ @timeout) do
    {_, pool, _} = repo.__pool__

    if :ets.member(pool, self) do
      raise "process already owns a worker"
    else
      supervisor = :ets.lookup_element(pool, :metadata, 2)
      {:ok, pid} = ServerSup.new_owner(supervisor)

      case GenServer.call(pid, {:ownership_checkout, strategy, timeout}) do
        {:ok, checkout} ->
          unless :ets.insert_new(pool, {self, pid, checkout}) do
            GenServer.call(pid, {:ownership_checkin, timeout}, timeout)
            raise "race condition"
          end
        {:error, _} = error ->
          error
      end
    end
  end

  def ownership_checkin(repo, timeout \\ @timeout) do
    {_, pool, _, } = repo.__pool__
    if :ets.member(pool, self) do
      [{_, pid, _}] = :ets.lookup(pool, self)
      GenServer.call(pid, {:ownership_checkin, timeout}, timeout)
    else
      raise "process doesn't own a worker"
    end
  end

  def checkout(pool, _timeout) do
    case :ets.lookup(pool, self) do
      [{_, _, {worker, mod_conn, mode}}] ->
        {:ok, worker, mod_conn, mode, 0}
      [] ->
        raise "..."
    end
  end

  def checkin(_pool, _worker, _timeout) do
    :ok
  end

  def break(pool, worker, timeout) do
    if :ets.member(pool, self) do
      [{:metadata, _supervisor, inner_pool, module}] = :ets.lookup(pool, :metadata)
      module.break(inner_pool, worker, timeout)
    else
      raise "..."
    end
  end

  def checkout_transaction(pool, timeout) do
    if :ets.member(pool, self) do
      [{:metadata, _supervisor, inner_pool, module}] = :ets.lookup(pool, :metadata)
      [{_, _, {worker, mod_conn, mode}}] = :ets.lookup(pool, self)
      module.open_transaction(inner_pool, worker, timeout)
      {:ok, worker, mod_conn, mode, 0}
    else
      raise "..."
    end
  end

  def open_transaction(_pool, _worker, _timeout) do
    raise "#{inspect __MODULE__}.open_transaction/3 should never be called"
  end

  def close_transaction(pool, worker, timeout) do
    if :ets.member(pool, self) do
      [{:metadata, _supervisor, inner_pool, module}] = :ets.lookup(pool, :metadata)
      module.close_transaction(inner_pool, worker, timeout)
    else
      raise "..."
    end
  end
end
