defmodule Ecto.Adapters.Poolboy.Worker do
  @moduledoc false

  use GenServer
  use Behaviour

  @type modconn :: {module :: atom, conn :: pid}

  def start_link({module, params}) do
    GenServer.start_link(__MODULE__, {module, params})
  end

  @spec open_transaction(pid, timeout) :: :ok
  def open_transaction(worker, timeout) do
    GenServer.call(worker, :open_transaction, timeout)
  end

  @spec close_transaction(pid) :: :ok
  def close_transaction(worker) do
    GenServer.cast(worker, :close_transaction)
  end

  @spec disconnect_transaction(pid, timeout) :: :ok
  def disconnect_transaction(worker, timeout) do
    GenServer.call(worker, :disconnect_transaction, timeout)
  end

  @spec transaction_mode(pid, :raw | :sandbox, timeout) ::
    :ok | {:error, :noconnect}
  def transaction_mode(worker, mode, timeout) do
    GenServer.call(worker, {:transaction_mode, mode}, timeout)
  end

  ## Callbacks

  def init({module, params}) do
    Process.flag(:trap_exit, true)
    lazy? = Keyword.get(params, :lazy, true)

    unless lazy? do
      case module.connect(params) do
        {:ok, conn} ->
          conn = conn
        _ ->
          :ok
      end
    end

    {:ok, %{conn: conn, params: params, transaction: nil, mode: :raw,
            module: module}}
  end

  ## Disconnect transaction

  def handle_call(:disconnect_transaction, _from, %{mode: :sandbox} = s) do
    {:reply, :ok, demonitor(s)}
  end

  def handle_call(:disconnect_transaction, _from, %{transaction: nil} = s) do
    {:stop, :notransaction, s}
  end

  def handle_call(:disconnect_transaction, _from, s) do
    s = s
      |> demonitor()
      |> disconnect()
    {:reply, :ok, s}
  end

  ## Mode change

  def handle_call({:transaction_mode, _}, _from, %{conn: nil} = s) do
    {:reply, {:error, :noconnect}, s}
  end
  def handle_call({:transaction_mode, :raw}, _from, %{mode: :sandbox} = s) do
    {:reply, :ok, %{s | mode: :raw}}
  end
  def handle_call({:transaction_mode, :sandbox}, _from, %{mode: :raw} = s) do
    {:reply, :ok, %{s | mode: :sandbox}}
  end
  def handle_call({:transaction_mode, mode}, _from, %{mode: mode} = s) do
    {:stop, :already_mode, s}
  end

  ## Lazy connection handling

  def handle_call(request, from, %{conn: nil, params: params, module: module} = s) do
    case module.connect(params) do
      {:ok, conn}   -> handle_call(request, from, %{s | conn: conn})
      {:error, err} -> {:reply, {:error, err}, s}
    end
  end

  ## Open transaction

  def handle_call(:open_transaction, {pid, _},
  %{transaction: nil, mode: mode} = s) do
    {:reply, {mode, modconn(s)}, monitor(pid, s)}
  end

  def handle_call(:open_transaction, from, %{transaction: {client, _}} = s) do
    if Process.is_alive?(client) do
      {:stop, :already_transaction, s}
    else
      s = s
        |> demonitor()
        |> disconnect()
      handle_call(:open_transaction, from, s)
    end
  end

  ## Close transaction

  def handle_cast(:close_transaction, %{mode: :sandbox} = s) do
    {:noreply, demonitor(s)}
  end

  def handle_cast(:close_transaction, %{transaction: nil} = s) do
    {:stop, :notransaction, s}
  end

  def handle_cast(:close_transaction, s) do
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
  def handle_info({:DOWN, ref, _, _, _},
  %{mode: :raw, transaction: {_, ref}} = s) do
    {:noreply, disconnect(%{s | transaction: nil})}
  end
  def handle_info({:DOWN, ref, _, _, _},
  %{mode: :sandbox, transaction: {_, ref}} = s) do
    {:noreply, %{s | transaction: nil}}
  end

  def handle_info(_info, s) do
    {:noreply, s}
  end

  def terminate(_reason, %{conn: conn, module: module}) do
    conn && module.disconnect(conn)
  end

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

  defp disconnect(%{conn: conn, module: module} = s) do
    conn && module.disconnect(conn)
    %{s | conn: nil, mode: :raw}
  end
end
