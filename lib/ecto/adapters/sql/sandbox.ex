defmodule Ecto.Adapters.SQL.Sandbox do
  @moduledoc """
  Start a pool with a single sandboxed SQL connection.
  """

  @behaviour Ecto.Adapters.Pool

  @typep log :: (%Ecto.LogEntry{} -> any())

  @doc """
  Starts a pool with a single sandboxed connections for the given SQL connection
  module and options.

    * `conn_mod` - The connection module, see `Ecto.Adapters.Connection`
    * `opts` - The options for the pool and the connections

  """
  @spec start_link(module, Keyword.t) :: {:ok, pid} | {:error, any}
  def start_link(module, params) do
    {:ok, _} = Application.ensure_all_started(:poolboy)
    opts = [worker_module: __MODULE__, size: 1, max_overflow: 0]
    {name, params} = Keyword.pop(params, :name)
    args = {module, params}
    if is_nil(name) do
        :poolboy.start_link(opts, args)
    else
        :poolboy.start_link([name: {:local, name}] ++ opts, args)
    end
  end

  @doc false
  @spec start_link({module, Keyword.t}) :: {:ok, pid} | {:error, any}
  def start_link({_, _} = args) do
    GenServer.start_link(__MODULE__, args)
  end

  @doc false
  @spec begin(pool, log, Keyword.t, timeout) ::
    :ok | {:error, :sandbox | :noproc} when pool: pid | atom
  def begin(pool, log, opts, timeout) do
    query(pool, :begin, log, opts, timeout)
  end

  @doc false
  @spec restart(pool, log, Keyword.t, timeout) ::
    :ok | {:error, :noproc} when pool: pid | atom
  def restart(pool, log, opts, timeout) do
    query(pool, :restart, log, opts, timeout)
  end

  @doc false
  @spec rollback(pool, log, Keyword.t, timeout) ::
    :ok | {:error, :noproc} when pool: pid | atom
  def rollback(pool, log, opts, timeout) do
    query(pool, :rollback, log, opts, timeout)
  end

  @doc false
  @spec mode(pool) :: :raw | :sandbox | :notransaction when pool: pid | atom
  def mode(pool) do
    case Process.get({__MODULE__, pool}) do
      :raw     -> :raw
      :sandbox -> :sandbox
      nil      -> :notransaction
    end
  end

  @doc false
  def checkout(pool, timeout) do
    checkout(pool, :run, timeout)
  end

  @doc false
  def checkin(pool, worker, _) do
    checkin(pool, worker)
  end

  @doc false
  def open_transaction(pool, timeout) do
    checkout(pool, :transaction, timeout)
  end

  @doc false
  def close_transaction(pool, worker, _) do
    try do
      GenServer.cast(worker, :checkin)
    after
      checkin(pool, worker)
    end
  end

  @doc false
  def break(pool, worker, timeout) do
    try do
      GenServer.call(worker, :break, timeout)
    after
      checkin(pool, worker)
    end
  end

  @doc false
  def stop(pool) do
    :poolboy.stop(pool)
  end

  ## GenServer

  @doc false
  def init({module, params}) do
    _ = Process.flag(:trap_exit, true)
    case module.connect(params) do
      {:ok, conn} ->
        {:ok, %{module: module, conn: conn, params: params, monitor: nil,
                mode: :raw}}
      {:error, reason} ->
        {:stop, reason}
    end
  end

  ## Checkout

  @doc false
  def handle_call({:checkout, :run}, _, %{monitor: nil, mode: mode} = s) do
    %{module: module, conn: conn} = s
    {:reply, {mode, {module, conn}}, s}
  end
  def handle_call({:checkout, :transaction}, {pid, _}, %{monitor: nil} = s) do
    %{mode: mode, module: module, conn: conn} = s
    mon = Process.monitor(pid)
    {:reply, {mode, {module, conn}}, %{s | monitor: mon}}
  end

  ## Break

  def handle_call(:break, _, %{monitor: nil, mode: :sandbox} = s) do
    {:reply, :ok, s}
  end
  def handle_call(:break, _, %{mode: :sandbox} =s) do
    {:reply, :ok, demonitor(s)}
  end
  def handle_call(:break, _, %{monitor: nil, mode: :raw} = s) do
    {:reply, :ok, reset(s)}
  end
  def handle_call(:break, _, %{mode: :raw} = s) do
    s = s
      |> demonitor()
      |> reset()
    {:reply, :ok, s}
  end

  ## Query

  def handle_call({:query, query, log, opts}, _, %{monitor: nil} = s) do
    {reply, s} = handle_query(query, log, opts, s)
    {:reply, reply, s}
  end

  ## Mode

  def handle_call(:mode, _, %{mode: mode} = s) do
    {:reply, mode, s}
  end

  ## New client when monitorring a transaction

  def handle_call(call, from, %{mode: :sandbox} = s) do
    handle_call(call, from, demonitor(s))
  end
  def handle_call(call, from, %{mode: :raw} = s) do
    s = s
      |> demonitor()
      |> reset()
    handle_call(call, from, s)
  end

  ## Checkin

  def handle_cast(:checkin, s) do
    {:noreply, demonitor(s)}
  end

  ## DOWN

  @doc false
  def handle_info({:DOWN, mon, _, _, _}, %{monitor: mon, mode: :raw} = s) do
    {:noreply, reset(%{s | monitor: nil})}
  end
  def handle_info({:DOWN, mon, _, _, _}, %{monitor: mon, mode: :sandbox} = s) do
    {:noreply, %{s | monitor: nil}}
  end

  ## EXIT

  def handle_info({:EXIT, conn, reason}, %{conn: conn} = s) do
    {:stop, reason, %{s | conn: nil}}
  end

  ## Info

  def handle_info(_, s) do
    {:noreply, s}
  end

  ## Terminate

  @doc false
  def terminate(_, %{module: module, conn: conn}) do
    conn && module.disconnect(conn)
  end

  ## Helpers


  defp checkout(pool, fun, timeout) do
    case :timer.tc(fn() -> do_checkout(pool, fun, timeout) end) do
      {queue_time, {mode, worker, mod_conn}} ->
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
      GenServer.call(worker, {:checkout, fun}, timeout)
    catch
      class, reason ->
        stack = System.stacktrace()
        :poolboy.checkin(pool, worker)
        :erlang.raise(class, reason, stack)
    else
      {mode, mod_conn} ->
        Process.put({__MODULE__, pool}, mode)
        {:ok, worker, mod_conn}
    end
  end

  def checkin(pool, worker) do
    _ = Process.delete({__MODULE__, pool})
    :poolboy.checkin(pool, worker)
  end

  defp query(pool, query, log, opts, timeout) do
    call(pool, {:query, query, log, opts}, timeout)
  end

  defp call(pool, call, timeout) do
    try do
      :poolboy.checkout(pool, true, timeout)
    catch
      {:noproc, _} ->
        {:error, :noproc}
    else
      worker ->
        call(pool, worker, call, timeout)
    end
  end

  defp call(pool, worker, call, timeout) do
    try do
      GenServer.call(worker, call, timeout)
    after
      :poolboy.checkin(pool, worker)
    end
  end

  defp demonitor(%{monitor: mon} = s) do
    Process.demonitor(mon, [:flush])
    %{s | monitor: nil}
  end

  def handle_query(query, log, opts, s) do
    query! = &query!(&1, &2, log, opts)
    case query do
      :begin    -> begin(s, query!)
      :restart  -> restart(s, query!)
      :rollback -> rollback(s, query!)
    end
  end

  defp begin(%{mode: :sandbox} = s, _) do
    {{:error, :sandbox}, s}
  end
  defp begin(%{mode: :raw, module: module} = s, query!) do
    begin_sql = module.begin_transaction()
    query!.(s, begin_sql)
    savepoint_sql = module.savepoint("ecto_sandbox")
    query!.(s, savepoint_sql)
    {:ok, %{s | mode: :sandbox}}
  end

  defp restart(%{mode: :raw} = s, query!), do: begin(s, query!)
  defp restart(%{mode: :sandbox, module: module} = s, query!) do
    sql = module.rollback_to_savepoint("ecto_sandbox")
    query!.(s, sql)
    {:ok, s}
  end

  defp rollback(%{mode: :raw} = s, _), do: {:ok, s}
  defp rollback(%{mode: :sandbox, module: module} = s, query!) do
    sql = module.rollback_to_savepoint("ecto_sandbox")
    query!.(s, sql)
    {:ok, %{s | mode: :raw}}
  end

  defp query!(%{module: module, conn: conn}, sql, log, opts) do
    log? = Keyword.get(opts, :log, true)
    {query_time, res} = :timer.tc(module, :query, [conn, sql, [], opts])
    if log? do
      entry = %Ecto.LogEntry{query: sql, params: [], result: res,
                            query_time: query_time, queue_time: nil}
      log.(entry)
    end
    case res do
      {:ok, _} ->
        :ok
      {:error, err} ->
        raise err
    end
  end

  defp reset(%{module: module, conn: conn, params: params} = s) do
    module.disconnect(conn)
    case module.connect(params) do
      {:ok, conn}     -> %{s | conn: conn}
      {:error, error} -> raise error
    end
  end
end
