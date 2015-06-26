defmodule Ecto.Adapters.SojournBroker.Worker do
  @moduledoc false

  use GenServer
  require Logger
  use Bitwise

  @timeout 5_000

  @spec start_link(module, Keyword.t) :: {:ok, pid}
  def start_link(module, params) do
    GenServer.start_link(__MODULE__, {module, params}, [])
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

  def init({module, opts}) do
    Process.flag(:trap_exit, true)
    worker_keys = [:name, :min_backoff, :max_backoff]
    {worker_opts, params} = Keyword.split(opts, worker_keys)
    broker = Keyword.fetch!(worker_opts, :name)
    tag = make_ref()
    min_backoff = Keyword.get(worker_opts, :min_backoff, 500)
    max_backoff = Keyword.get(worker_opts, :max_backoff, 5_000)
    backoff_threshold = div(max_backoff, 3)

    s = %{conn: nil, module: module, params: params, transaction: nil,
          broker: Process.whereis(broker), tag: tag, ref: nil, fun: nil,
          monitor: nil, backoff: min_backoff, min_backoff: min_backoff,
          max_backoff: max_backoff, backoff_threshold: backoff_threshold}
    send(self(), {tag, :connect})
    {:ok, s}
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
    {:noreply, %{s | fun: fun, ref: ref, monitor: mon}}
  end

  ## drop

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

  def terminate(_reason, %{conn: conn, module: module}) do
    conn && module.disconnect(conn)
  end

  ## Helpers

  defp connect(%{conn: nil} = s) do
    %{module: module, params: params, min_backoff: min_backoff} = s
    case module.connect(params) do
      {:ok, conn} ->
        ask(%{s | conn: conn, backoff: min_backoff})
      {:error, error} ->
        log_connect_error(error, s)
        backoff(s)
    end
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

  defp cancel_or_await(%{tag: tag}) do
    case :sbroker.cancel(tag, @timeout) do
      false -> :cancelled
      1     -> :sbroker.await(tag, 0)
    end
  end

  defp demonitor(%{monitor: mon} = s) do
    Process.demonitor(mon, [:flush])
    %{s | monitor: nil, fun: nil, ref: nil}
  end

  defp disconnect(%{module: module, conn: conn} = s) do
    module.disconnect(conn)
    %{s | conn: nil}
  end
end
