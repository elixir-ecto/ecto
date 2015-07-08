defmodule Ecto.Pools.Poolboy.Worker do
  @moduledoc false

  use GenServer
  use Behaviour
  alias Ecto.Adapters.Connection

  @type modconn :: {module :: atom, conn :: pid}

  @spec start_link({module, Keyword.t}) :: {:ok, pid}
  def start_link({module, params}) do
    GenServer.start_link(__MODULE__, {module, params}, [])
  end

  @spec checkout(pid, fun, timeout) ::
  {:ok, modconn} | {:error, Exception.t} when fun: :run | :transaction
  def checkout(worker, fun, timeout) do
    GenServer.call(worker, {:checkout, fun}, timeout)
  end

  @spec checkin(pid) :: :ok
  def checkin(worker) do
    GenServer.cast(worker, :checkin)
  end

  @spec break(pid, timeout) :: :ok
  def break(worker, timeout) do
    GenServer.call(worker, :break, timeout)
  end

  ## Callbacks

  def init({module, opts}) do
    Process.flag(:trap_exit, true)
    {opts, params} = Keyword.split(opts, [:lazy, :shutdown])
    lazy?    = Keyword.get(opts, :lazy, true)
    shutdown = Keyword.get(opts, :shutdown, 5_000)

    unless lazy? do
      case Connection.connect(module, params) do
        {:ok, conn} ->
          conn = conn
        _ ->
          :ok
      end
    end

    {:ok, %{conn: conn, params: params, shutdown: shutdown, transaction: nil,
            module: module}}
  end

  ## Break

  def handle_call(:break, _from, s) do
    s = s
      |> demonitor()
      |> disconnect()
    {:reply, :ok, s}
  end

  ## Lazy connection handling

  def handle_call(request, from, %{conn: nil, params: params, module: module} = s) do
    case Connection.connect(module, params) do
      {:ok, conn}   -> handle_call(request, from, %{s | conn: conn})
      {:error, err} -> {:reply, {:error, err}, s}
    end
  end

  ## Checkout

  def handle_call({:checkout, :run}, _, s) do
    {:reply, {:ok, modconn(s)}, s}
  end

  ## Open transaction

  def handle_call({:checkout, :transaction}, from, %{transaction: nil} = s) do
    {pid, _} = from
    {:reply, {:ok, modconn(s)}, monitor(pid, s)}
  end

  def handle_call({:checkout, :transaction} = checkout, from, s) do
    {client, _} = s.transaction
    if Process.is_alive?(client) do
      handle_call(checkout, from, demonitor(s))
    else
      s = s
        |> demonitor()
        |> disconnect()
      handle_call(checkout, from, s)
    end
  end

  ## Close transaction


  def handle_cast(:checkin, %{transaction: nil} = s) do
    {:stop, :notransaction, s}
  end

  def handle_cast(:checkin, s) do
    {:noreply, demonitor(s)}
  end

  ## Info

  # The connection crashed. We don't need to notify
  # the client if we have an open transaction because
  # it will fail with noproc anyway.
  def handle_info({:EXIT, conn, _reason}, %{conn: conn} = s) do
    s = %{s | conn: nil}
      |> disconnect()
    {:noreply, s}
  end

  # The transaction owner crashed without closing.
  # We need to assume we don't know the connection state.
  def handle_info({:DOWN, ref, _, _, _}, %{transaction: {_, ref}} = s) do
    {:noreply, disconnect(%{s | transaction: nil})}
  end

  def handle_info(_info, s) do
    {:noreply, s}
  end

  def terminate(_reason, s), do: disconnect(s)

  ## Helpers

  defp modconn(%{conn: conn, module: module}) do
    {module, conn}
  end

  defp monitor(pid,s) do
    ref = Process.monitor(pid)
    %{s | transaction: {pid, ref}}
  end

  defp demonitor(%{transaction: nil} = s), do: s
  defp demonitor(%{transaction: {_, ref}} = s) do
    Process.demonitor(ref, [:flush])
    %{s | transaction: nil}
  end

  defp disconnect(%{conn: conn, shutdown: shutdown} = s) do
    _ = conn && Connection.shutdown(conn, shutdown)
    %{s | conn: nil}
  end
end
