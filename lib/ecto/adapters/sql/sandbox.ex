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
  def start_link(conn_mod, opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, {conn_mod, opts}, [name: name])
  end

  @doc false
  @spec begin(pool, log, Keyword.t, timeout) ::
    :ok | {:error, :sandbox} when pool: pid | atom
  def begin(pool, log, opts, timeout) do
    query(pool, :begin, log, opts, timeout)
  end

  @doc false
  @spec restart(pool, log, Keyword.t, timeout) :: :ok when pool: pid | atom
  def restart(pool, log, opts, timeout) do
    query(pool, :restart, log, opts, timeout)
  end

  @doc false
  @spec rollback(pool, log, Keyword.t, timeout) :: :ok when pool: pid | atom
  def rollback(pool, log, opts, timeout) do
    query(pool, :rollback, log, opts, timeout)
  end

  @doc false
  @spec mode(pool, timeout) :: :raw | :sandbox when pool: pid | atom
  def mode(pool, timeout \\ 5_000) do
    GenServer.call(pool, :mode, timeout)
  end

  @doc false
  def checkout(pool, timeout) do
    checkout(pool, :run, timeout)
  end

  @doc false
  def checkin(pool, ref, _) do
    GenServer.cast(pool, {:checkin, ref})
  end

  @doc false
  def open_transaction(pool, timeout) do
    checkout(pool, :transaction, timeout)
  end

  @doc false
  def close_transaction(pool, ref, _) do
    GenServer.cast(pool, {:checkin, ref})
  end

  @doc false
  def break(pool, ref, timeout) do
    GenServer.call(pool, {:break, ref}, timeout)
  end

  @doc false
  def stop(pool) do
    GenServer.call(pool, :stop)
  end

  ## GenServer

  @doc false
  def init({module, params}) do
    _ = Process.flag(:trap_exit, true)
    case module.connect(params) do
      {:ok, conn} ->
        {:ok, %{module: module, conn: conn, clients: :queue.new(), fun: nil,
              ref: nil, monitor: nil, mode: :raw, queries: :queue.new()}}
      {:error, reason} ->
        {:stop, reason}
    end
  end

  ## Checkout

  @doc false
  def handle_call({:checkout, ref, fun}, {pid, _}, %{ref: nil} = s) do
    %{module: module, conn: conn} = s
    mon = Process.monitor(pid)
    {:reply, {:ok, {module, conn}}, %{s | fun: fun, ref: ref, monitor: mon}}
  end
  def handle_call({:checkout, ref, fun}, from, %{clients: clients} = s) do
    {pid, _} = from
    mon = Process.monitor(pid)
    {:noreply, %{s | clients: :queue.in({from, ref, fun, mon}, clients)}}
  end

  ## Break

  def handle_call({:break, ref}, from, %{ref: ref} = s) do
    s = demonitor(s)
    GenServer.reply(from, :ok)
    s = s
      |> dequeue()
    {:noreply, s}
  end

  ## Query

  def handle_call({:query, query, log, opts}, _, %{ref: nil} = s) do
    {reply, s} = handle_query(query, log, opts, s)
    {:reply, reply, s}
  end

  def handle_call({:query, query, log, opts}, from, %{queries: queries} = s) do
    {:noreply, %{s | queries: :queue.in({query, log, opts, from}, queries)}}
  end

  ## Mode

  def handle_call(:mode, _, %{mode: mode} = s) do
    {:reply, mode, s}
  end

  ## Stop

  def handle_call(:stop, _, s) do
    {:stop, :normal, :ok, s}
  end

  ## Cancel

  @doc false
  def handle_cast({:cancel, ref}, %{ref: ref} = s) do
    handle_cast({:checkin, ref}, s)
  end
  def handle_cast({:cancel, ref}, %{clients: clients} = s) do
    {:noreply, %{s | clients: :queue.filter(&cancel(&1, ref), clients)}}
  end

  ## Checkin

  def handle_cast({:checkin, ref}, %{ref: ref} = s) do
    s = s
      |> demonitor()
      |> dequeue()
    {:noreply, s}
  end

  ## DOWN

  @doc false
  def handle_info({:DOWN, mon, _, _, _}, %{monitor: mon, fun: :run} = s) do
    {:noreply, dequeue(%{s | fun: nil, monitor: nil, ref: nil})}
  end
  def handle_info({:DOWN, mon, _, _, _}, %{monitor: mon, mode: :raw} = s) do
    s = %{s | fun: nil, monitor: nil, ref: nil}
      |> reset()
      |> dequeue()
    {:noreply, s}
  end
  def handle_info({:DOWN, mon, _, _, _}, %{monitor: mon, mode: :sandbox} = s) do
    s = %{s | fun: nil, monitor: nil, ref: nil}
      |> dequeue()
    {:noreply, s}
  end
  def handle_info({:DOWN, mon, _, _, _}, %{clients: clients} = s) do
    down = fn({_, _, _, mon2}) -> mon2 !== mon end
    {:noreply, %{s | clients: :queue.filter(down, clients)}}
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
    ref = make_ref()
    case :timer.tc(fn() -> do_checkout(pool, ref, fun, timeout) end) do
      {queue_time, {:ok, mod_conn}} ->
        {:ok, ref, mod_conn, queue_time}
      {_, {:error, _} = error} ->
        error
    end
  end

  defp do_checkout(pool, ref, fun, timeout) do
    try do
      GenServer.call(pool, {:checkout, ref, fun}, timeout)
    catch
      :exit, {:timeout, _} = reason ->
        GenServer.cast(pool, {:cancel, ref})
        exit(reason)
      :exit, {:noproc, _} ->
        {:error, :noproc}
    end
  end

  defp query(pool, query, log, opts, timeout) do
    GenServer.call(pool, {:query, query, log, opts}, timeout)
  end

  defp cancel({_, ref, _, mon}, ref) do
    Process.demonitor(mon, [:flush])
    false
  end
  defp cancel(_, _) do
    true
  end

  defp demonitor(%{monitor: mon} = s) do
    Process.demonitor(mon, [:flush])
    %{s | fun: nil, ref: nil, monitor: nil}
  end

  defp dequeue(%{queries: queries} = s) do
    case :queue.out(queries) do
      {{:value, {query, log, opts, from}}, queries} ->
        {reply, s} = handle_query(query, log, opts, %{s | queries: queries})
        GenServer.reply(from, reply)
        dequeue(s)
      {:empty, _} ->
        dequeue_client(s)
    end
  end

  def handle_query(query, log, opts, s) do
    query! = &query!(&1, &2, log, opts)
    case query do
      :begin    -> begin(s, query!)
      :restart  -> restart(s, query!)
      :rollback -> rollback(s, query!)
    end
  end

  defp dequeue_client(%{ref: nil, clients: clients} = s) do
    case :queue.out(clients) do
      {{:value, {from, ref, fun, mon}}, clients} ->
        %{module: module, conn: conn} = s
        GenServer.reply(from, {:ok, {module, conn}})
        %{s | ref: ref, fun: fun, monitor: mon, clients: clients}
      {:empty, _} ->
        s
    end
  end

  defp begin(%{ref: nil, mode: :sandbox} = s, _) do
    {{:error, :sandbox}, s}
  end
  defp begin(%{ref: nil, mode: :raw, module: module} = s, query!) do
    begin_sql = module.begin_transaction()
    query!.(s, begin_sql)
    savepoint_sql = module.savepoint("ecto_sandbox")
    query!.(s, savepoint_sql)
    {:ok, %{s | mode: :sandbox}}
  end

  defp restart(%{ref: nil, mode: :raw} = s, query!), do: begin(s, query!)
  defp restart(%{ref: nil, mode: :sandbox, module: module} = s, query!) do
    sql = module.rollback_to_savepoint("ecto_sandbox")
    query!.(s, sql)
    {:ok, s}
  end

  defp rollback(%{ref: nil, mode: :raw} = s, _), do: {:ok, s}
  defp rollback(%{ref: nil, mode: :sandbox, module: module} = s, query!) do
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
