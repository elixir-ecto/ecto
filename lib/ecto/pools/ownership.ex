defmodule Ecto.Pools.Ownership do

  defmodule Strategy do
    use Behaviour
    alias Ecto.Pool

    defcallback ownership_checkout(module, pid) :: Pool.mode
    defcallback ownership_checkin(module, pid) :: Pool.mode
  end

  defmodule Server do
    use GenServer

    @behaviour Ecto.Pool
    @timeout 5_000

    def start_link(_, _) do
      raise "#{inspect __MODULE__}.start_link/2 should never be called"
    end

    def start_link(adapter, repo, opts) do
      pool     = Keyword.fetch!(opts, :pool)
      name     = Keyword.fetch!(opts, :pool_name)
      opts     = Keyword.put(opts, :pool_name, Module.concat(name, Inner))

      adapter_opts = {adapter, repo, opts}
      GenServer.start_link(__MODULE__, {pool, adapter_opts}, [name: name])
    end

    def ownership_checkout(pool, strategy, timeout \\ @timeout) do
      case GenServer.call(pool, {:ownership_checkout, strategy, timeout}, timeout) do
        :ok ->
          :ok
        {:error, :already_checked_out} ->
          raise ArgumentError, "process already owns a worker"
      end
    end

    def ownership_checkin(pool, timeout \\ @timeout) do
      case GenServer.call(pool, {:ownership_checkin, timeout}, timeout) do
        :ok ->
          :ok
        {:error, :not_checked_out} ->
          raise ArgumentError, "process doesn't own a worker"
      end
    end

    def checkout(pool, timeout) do
      {worker, mod_conn, mode} =
        GenServer.call(pool, :get_checkout, timeout)
        |> maybe_raise
      # TODO: queue_time
      {:ok, worker, mod_conn, mode, 0}
    end

    def checkin(_pool, _worker, _timeout) do
      :ok
    end

    def break(pool, worker, timeout) do
      GenServer.call(pool, {:break, worker, timeout}, timeout)
      |> maybe_raise
    end

    def checkout_transaction(pool, timeout) do
      {fun, {worker, mod_conn, mode}} =
        GenServer.call(pool, {:open_transaction, timeout}, timeout)
        |> maybe_raise

      fun.()
      # TODO: queue_time
      {:ok, worker, mod_conn, mode, 0}
    end

    def open_transaction(_pool, _worker, _timeout) do
      raise "#{inspect __MODULE__}.open_transaction/3 should never be called"
    end

    def close_transaction(pool, worker, timeout) do
      fun =
        GenServer.call(pool, {:close_transaction, worker, timeout}, timeout)
        |> maybe_raise

      fun.()
    end

    defp maybe_raise({:error, :not_checked_out}),
      do: raise(ArgumentError, "process doesn't own a worker")
    defp maybe_raise(:ok),
      do: :ok
    defp maybe_raise({:ok, value}),
      do: value


    def init({module, {adapter, repo, opts}}) do
      {:ok, pid} = adapter.start_link(repo, opts)
      {:ok, %{module: module,
              pool: pid,
              owners: %{}}}
    end

    def handle_call({:ownership_checkout, strategy, timeout}, {pid, _ref}, s) do
      case Map.fetch(s.owners, pid) do
        {:ok, _} ->
          {:reply, {:error, :already_checked_out}, s}
        :error ->
          checkout = retrieve_worker(timeout, s)
          {worker, {module, conn}, :default, _queue_time} = checkout
          mode = if strategy,
                   do: strategy.ownership_checkout(module, conn),
                 else: :default


          checkout = {worker, {module, conn}, mode}
          s = monitor_owner(pid, checkout, strategy, s)
          {:reply, :ok, s}
      end
    end

    def handle_call({:ownership_checkin, timeout}, {pid, _ref}, s) do
      case Map.fetch(s.owners, pid) do
        {:ok, {_ref, {worker, {module, conn}, _mode}, strategy}} ->
          if strategy, do: strategy.ownership_checkin(module, conn)
          s.module.checkin(s.pool, worker, timeout)
          {:reply, :ok, s}
        :error ->
          {:reply, {:error, :not_checked_out}, s}
      end
    end

    def handle_call(:get_checkout, {pid, _ref}, s) do
      maybe_get_worker(pid, s, fn {_ref, checkout, _strategy} ->
        {:reply, {:ok, checkout}, s}
      end)
    end

    def handle_call({:break, worker, timeout}, {pid, _ref}, s) do
      maybe_get_worker(pid, s, fn {_ref, {my_worker, _mod_conn, _mode}, _strategy} ->
        ^my_worker = worker
        s.module.break(s.pool, worker, timeout)
        # Should we do same as :DOWN here? I am thinking no
        {:reply, :ok, s}
      end)
    end

    def handle_call({:open_transaction, timeout}, {pid, _ref}, s) do
      maybe_get_worker(pid, s, fn {_ref, {worker, _mod_conn, _mode} = checkout, _strategy} ->
        fun = fn -> s.module.open_transaction(s.pool, worker, timeout) end
        {:reply, {:ok, {fun, checkout}}, s}
      end)
    end

    def handle_call({:close_transaction, worker, timeout}, {pid, _ref}, s) do
      maybe_get_worker(pid, s, fn {_ref, {my_worker, _mod_conn, _mode}, _strategy} ->
        ^my_worker = worker
        fun = fn -> s.module.close_transaction(s.pool, worker, timeout) end
        {:reply, {:ok, fun}, s}
      end)
    end

    def handle_info({:DOWN, ref, :process, pid, _reason}, s) do
      case Map.fetch(s.owners, pid) do
        {:ok, {^ref, {worker, {module, conn}, _mode}, strategy}} ->
          if strategy, do: strategy.ownership_checkin(module, conn)
          s.module.checkin(s.pool, worker, @timeout)
          {:noreply, s}
        :error ->
          {:noreply, s}
      end
    end

    defp maybe_get_worker(owner, s, fun) do
      case Map.fetch(s.owners, owner) do
        {:ok, value} ->
          fun.(value)
        :error ->
          {:reply, {:error, :not_checked_out}, s}
      end
    end

    defp retrieve_worker(timeout, s) do
      {:ok, worker, conn, mode, queue_time} = s.module.checkout(s.pool, timeout)
      {worker, conn, mode, queue_time}
    end

    defp monitor_owner(owner, checkout, strategy, s) do
      ref = Process.monitor(owner)
      %{s | owners: Map.put(s.owners, owner, {ref, checkout, strategy})}
    end
  end
end
