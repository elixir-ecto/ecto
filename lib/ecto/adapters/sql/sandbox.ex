defmodule Ecto.Adapters.SQL.Sandbox do
  @moduledoc """
  Start a pool with a single sandboxed SQL connection.

  ### Options

  * `:shutdown` - The shutdown method for the connections (default: 5000) (see Supervisor.Spec)

  """

  alias Ecto.Adapters.Connection
  @behaviour Ecto.Pool

  @typep log :: (%Ecto.LogEntry{} -> any())

  @doc """
  Starts a pool with a single sandboxed connections for the given SQL connection
  module and options.

    * `conn_mod` - The connection module, see `Ecto.Adapters.Connection`
    * `opts` - The options for the pool and the connections

  """
  @spec start_link(module, Keyword.t) :: {:ok, pid} | {:error, any}
  def start_link(conn_mod, opts) do
    {name, opts} = Keyword.pop(opts, :pool_name)
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

  ## GenServer

  @doc false
  def init({module, opts}) do
    _ = Process.flag(:trap_exit, true)
    {shutdown, params} = Keyword.pop(opts, :shutdown, 5_000)
    {:ok, %{module: module, conn: nil, queue: :queue.new(), fun: nil,
            ref: nil, monitor: nil, mode: :raw, params: params,
            shutdown: shutdown}}
  end

  ## Lazy connect

  def handle_call(req, from, %{conn: nil} = s) do
    %{module: module, params: params} = s
    case Connection.connect(module, params) do
      {:ok, conn} ->
        handle_call(req, from, %{s | conn: conn})
      {:error, reason} ->
        {:stop, reason, s}
    end
  end

  ## Checkout

  @doc false
  def handle_call({:checkout, ref, fun}, {pid, _}, %{ref: nil} = s) do
    %{module: module, conn: conn} = s
    mon = Process.monitor(pid)
    {:reply, {:ok, {module, conn}}, %{s | fun: fun, ref: ref, monitor: mon}}
  end
  def handle_call({:checkout, ref, fun}, {pid, _} = from, %{queue: q} = s) do
    mon = Process.monitor(pid)
    {:noreply, %{s | queue: :queue.in({:checkout, from, ref, fun, mon}, q)}}
  end

  ## Break

  def handle_call({:break, ref}, from, %{mode: :raw, ref: ref} = s) do
    s = demonitor(s)
    GenServer.reply(from, :ok)
    s = s
      |> reset()
      |> dequeue()
    {:noreply, s}
  end
  def handle_call({:break, ref}, from, %{mode: :sandbox, ref: ref} = s) do
    s = demonitor(s)
    GenServer.reply(from, :ok)
    {:noreply, dequeue(s)}
  end

  ## Query

  def handle_call({:query, query, log, opts}, _, %{ref: nil} = s) do
    {reply, s} = handle_query(query, log, opts, s)
    {:reply, reply, s}
  end

  def handle_call({:query, query, log, opts}, from, %{queue: q} = s) do
    {:noreply, %{s | queue: :queue.in({query, log, opts, from}, q)}}
  end

  ## Mode

  def handle_call(:mode, _, %{mode: mode} = s) do
    {:reply, mode, s}
  end

  ## Cancel

  @doc false
  def handle_cast({:cancel, ref}, %{ref: ref} = s) do
    handle_cast({:checkin, ref}, s)
  end
  def handle_cast({:cancel, ref}, %{queue: q} = s) do
    {:noreply, %{s | queue: :queue.filter(&cancel(&1, ref), q)}}
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
  def handle_info({:DOWN, mon, _, _, _}, %{queue: q} = s) do
    {:noreply, %{s | queue: :queue.filter(&down(&1, mon), q)}}
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
  def terminate(_, %{conn: conn, shutdown: shutdown}) do
    conn && Connection.shutdown(conn, shutdown)
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

  defp cancel({:checkout, _, ref, _, mon}, ref) do
    Process.demonitor(mon, [:flush])
    false
  end
  defp cancel(_, _) do
    true
  end

  defp down({:checkout, _, _, _, mon}, mon) do
    false
  end
  defp down(_, _) do
    true
  end

  defp demonitor(%{monitor: mon} = s) do
    Process.demonitor(mon, [:flush])
    %{s | fun: nil, ref: nil, monitor: nil}
  end

  defp dequeue(%{queue: q} = s) do
    case :queue.out(q) do
      {{:value, {:checkout, from, ref, fun, mon}}, q} ->
        %{module: module, conn: conn} = s
        GenServer.reply(from, {:ok, {module, conn}})
        %{s | ref: ref, fun: fun, monitor: mon, queue: q}
      {{:value, {query, log, opts, from}}, q} ->
        {reply, s} = handle_query(query, log, opts, %{s | queue: q})
        GenServer.reply(from, reply)
        dequeue(s)
      {:empty, _} ->
        s
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
    sql = module.rollback()
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

  defp reset(s) do
    %{module: module, conn: conn, params: params, shutdown: shutdown} = s
    Connection.shutdown(conn, shutdown)
    case Connection.connect(module, params) do
      {:ok, conn}     -> %{s | conn: conn}
      {:error, error} -> raise error
    end
  end
end
