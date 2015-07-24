defmodule Ecto.Pools.SojournBroker.Worker do
  @moduledoc false

  use GenServer
  use Bitwise

  require Logger
  alias Ecto.Adapters.Connection

  @timeout 5_000

  @spec start_link(module, module, Keyword.t) :: {:ok, pid}
  def start_link(module, broker, params) do
    GenServer.start_link(__MODULE__, {module, broker, params}, [])
  end

  @spec mod_conn(pid, reference, timeout) ::
    {:ok, {module, pid}} | {:error, :noconnect}
  def mod_conn(worker, ref, timeout) do
    GenServer.call(worker, {:mod_conn, ref}, timeout)
  end

  @spec break(pid, reference, timeout) :: :ok
  def break(worker, ref, _) do
    GenServer.cast(worker, {:break, ref})
  end

  @spec done(pid, reference) :: :ok
  def done(worker, ref) do
    GenServer.cast(worker, {:done, ref})
  end

  ## Callbacks

  def init({module, broker, opts}) do
    Process.flag(:trap_exit, true)
    worker_keys = [:name, :lazy, :shutdown, :min_backoff, :max_backoff]
    {worker_opts, params} = Keyword.split(opts, worker_keys)
    tag = make_ref()
    min_backoff = Keyword.get(worker_opts, :min_backoff, 500)
    max_backoff = Keyword.get(worker_opts, :max_backoff, 5_000)
    backoff_threshold = div(max_backoff, 3)
    lazy = Keyword.get(worker_opts, :lazy, true)
    shutdown = Keyword.get(worker_opts, :shutdown, 5_000)

    # Seed random number generator for backoff. Can't use `now()` since it warns on Erlang 18.
    {_, sec, micro} = :os.timestamp()
    :random.seed({sec, micro, :erlang.phash2([make_ref()])})

    s = %{conn: nil, module: module, params: params, transaction: nil,
          broker: Process.whereis(broker), tag: tag, ref: nil, fun: nil,
          monitor: nil, backoff: min_backoff, min_backoff: min_backoff,
          max_backoff: max_backoff, backoff_threshold: backoff_threshold,
          lazy: lazy, shutdown: shutdown}

    if lazy do
      {:ok, lazy_ask(s)}
    else
      send(self(), {tag, :connect})
      {:ok, s}
    end
  end

  ## Module/Connection

  def handle_call({:mod_conn, ref}, _, %{ref: ref, conn: nil} = s) do
    {:reply, {:error, :noconnect}, s}
  end
  def handle_call({:mod_conn, ref}, _, %{ref: ref} = s) do
    %{module: module, conn: conn} = s
    {:reply, {:ok, {module, conn}}, s}
  end

  ## Break

  def handle_cast({:break, ref}, %{ref: ref, conn: nil} = s) do
    s = s
    |> demonitor()
    |> connect()
    {:noreply, s}
  end
  def handle_cast({:break, ref}, %{ref: ref} = s) do
    s = s
    |> demonitor()
    |> disconnect()
    |> connect()
    {:noreply, s}
  end

  ## Done

  def handle_cast({:done, ref}, %{ref: ref, conn: nil} = s) do
    s = s
      |> demonitor()
      |> connect()
    {:noreply, s}
  end
  def handle_cast({:done, ref}, %{ref: ref} = s) do
    s = s
      |> demonitor()
      |> ask()
    {:noreply, s}
  end

  ## connnect

  def handle_info({tag, :connect}, %{tag: tag, ref: nil} = s) do
    {:noreply, connect(s)}
  end

  ## EXIT

  def handle_info({:EXIT, conn, _}, %{conn: conn} = s) when is_pid(conn) do
    {:noreply, conn_exit(s)}
  end

  ## DOWN

  def handle_info({:DOWN, mon, _, _, _}, %{monitor: mon, conn: nil} = s) do
    {:noreply, connect(%{s | monitor: nil, fun: nil, ref: nil})}
  end
  def handle_info({:DOWN, mon, _, _, _}, %{monitor: mon, fun: :run} = s) do
    {:noreply, ask(%{s | fun: nil, ref: nil, monitor: nil})}
  end
  def handle_info({:DOWN, mon, _, _, _}, %{monitor: mon} = s) do
    s = %{s | monitor: nil, fun: nil, ref: nil}
    |> disconnect()
    |> connect()
    {:noreply, s}
  end

  ## go

  def handle_info({tag, {:go, ref, info, _, _}},%{tag: tag, ref: nil} = s) do
    {fun, pid} = info
    mon = Process.monitor(pid)
    s = %{s | fun: fun, ref: ref, monitor: mon}
    if s.lazy do
      {:noreply, lazy_connect(s)}
    else
      {:noreply, s}
    end
  end

  ## drop

  def handle_info({tag, {:drop, _}}, %{tag: tag, lazy: true} = s) do
    {:noreply, connect(%{s | lazy: false})}
  end
  def handle_info({tag, {:drop, _}}, %{tag: tag, ref: nil} = s) do
    s = s
      |> disconnect()
      |> connect()
    {:noreply, s}
  end

  ## Info

  def handle_info(_info, s) do
    {:noreply, s}
  end

  def terminate(_reason, %{conn: conn} = s) do
    conn && disconnect(s)
  end

  ## Helpers

  defp lazy_connect(%{lazy: true, conn: nil} = s) do
    %{module: module, params: params} = s
    case Connection.connect(module, params) do
      {:ok, conn} ->
        %{s | lazy: false, conn: conn}
      {:error, error} ->
        log_connect_error(error, s)
        %{s | lazy: false}
    end
  end

  defp connect(%{conn: nil} = s) do
    %{module: module, params: params, min_backoff: min_backoff} = s
    case Connection.connect(module, params) do
      {:ok, conn} ->
        ask(%{s | conn: conn, backoff: min_backoff})
      {:error, error} ->
        log_connect_error(error, s)
        backoff(s)
    end
  end

  defp lazy_ask(%{lazy: true, conn: nil, broker: broker, tag: tag} = s) do
    _ = :sbroker.async_ask_r(broker, {self(), :lazy}, tag)
    s
  end

  defp ask(%{ref: nil} = s) do
    %{broker: broker, module: module, conn: conn, tag: tag} = s
    _ = :sbroker.async_ask_r(broker, {self(), {module, conn}}, tag)
    s
  end

  defp log_connect_error(error, %{module: module, params: params}) do
    Logger.error(fn() ->
      [inspect(module), " failed to connect with parameters ", inspect(params),
       ?\n | inspect_error(error)]
    end)
  end

  defp inspect_error({'EXIT', reason}) do
    Exception.format_exit(reason)
  end
  defp inspect_error(reason) do
    if Exception.exception?(reason) do
      Exception.format_banner(:error, reason)
    else
      Exception.format_banner(:exit, reason)
    end
  end

  defp backoff(%{tag: tag} = s) do
    backoff = get_backoff(s)
    :erlang.send_after(backoff, self(), {tag, :connect})
    %{s | backoff: backoff}
  end

  ## random backoff where the next value is uniformal distributed with
  ## [n, 3n], unless 3n > max and then [div(max, 3), max]
  defp get_backoff(%{threshold: 0, max_backoff: max}) do
    max
  end
  defp get_backoff(%{backoff: backoff, backoff_threshold: threshold})
  when backoff > threshold do
    next_backoff(threshold)
  end
  defp get_backoff(%{backoff: backoff}) do
    next_backoff(backoff)
  end

  defp next_backoff(backoff) do
    width = backoff >>> 1
    backoff + :random.uniform(width + 1) - 1
  end

  defp conn_exit(%{ref: nil} = s) do
    case cancel_or_await(s) do
      :cancelled ->
        connect(%{s | conn: nil})
      {:go, ref, {fun, pid}, _, _} ->
        mon = Process.monitor(pid)
        %{s | mon: mon, ref: ref, fun: fun, conn: nil}
      {:drop, _} ->
        connect(%{s | conn: nil})
    end
  end
  defp conn_exit(s) do
    %{s | conn: nil}
  end

  defp cancel_or_await(%{broker: broker, tag: tag}) do
    case :sbroker.cancel(broker, tag, @timeout) do
      false -> :sbroker.await(tag, 0)
      1     -> :cancelled
    end
  end

  defp demonitor(%{monitor: mon} = s) do
    Process.demonitor(mon, [:flush])
    %{s | monitor: nil, fun: nil, ref: nil}
  end

  defp disconnect(%{conn: conn, shutdown: shutdown} = s) do
    _ = Connection.shutdown(conn, shutdown)
    %{s | conn: nil}
  end
end
