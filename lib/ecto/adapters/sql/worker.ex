defmodule Ecto.Adapters.SQL.Worker do
  @moduledoc false
  use GenServer

  @type modconn :: {module :: atom, conn :: pid}

  def start_link({module, args}) do
    GenServer.start_link(__MODULE__, {module, args})
  end

  def start({module, args}) do
    GenServer.start(__MODULE__, {module, args})
  end

  @doc """
  Asks for the module and the underlying connection process.
  """
  @spec ask(pid, timeout) :: {:ok, modconn} | {:error, Exception.t}
  def ask(worker, timeout) do
    GenServer.call(worker, :ask, timeout)
  end

  @doc """
  Asks for the module and the underlying connection process.
  """
  @spec ask!(pid, timeout) :: modconn | no_return
  def ask!(worker, timeout) do
    case ask(worker, timeout) do
      {:ok, modconn} -> modconn
      {:error, err}  -> raise err
    end
  end

  @doc """
  Opens a transaction.

  Invoked when the client wants to open up a connection.

  The worker process starts to monitor the caller and
  will wipeout all connection the connection in case of
  crashes.
  """
  @spec open_transaction(pid, timeout) :: {:ok, modconn} | {:sandbox, modconn} | {:error, Exception.t}
  def open_transaction(worker, timeout) do
    GenServer.call(worker, :open_transaction, timeout)
  end

  @doc """
  Closes a transaction.

  Invoked when a connection has been successfully closed.
  """
  @spec close_transaction(pid, timeout) :: :not_open | :closed
  def close_transaction(worker, timeout) do
    GenServer.call(worker, :close_transaction, timeout)
  end

  @doc """
  Breaks a transaction.

  Automatically forces the worker to disconnect unless
  in sandbox mode.
  """
  @spec break_transaction(pid, timeout) :: :broken | :not_open | :sandbox
  def break_transaction(worker, timeout) do
    GenServer.call(worker, :break_transaction, timeout)
  end

  @doc """
  Starts a sandbox transaction that lasts through the life-cycle
  of the worker.
  """
  @spec sandbox_transaction(pid, timeout) :: {:ok, modconn} | :sandbox | :already_open
  def sandbox_transaction(worker, timeout) do
    GenServer.call(worker, :sandbox_transaction, timeout)
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

    {:ok, %{conn: conn, params: params, transaction: :closed, module: module}}
  end

  ## Break transaction

  def handle_call(:break_transaction, _from, %{transaction: :sandbox} = s) do
    {:reply, :sandbox, s}
  end

  def handle_call(:break_transaction, _from, %{transaction: :closed} = s) do
    {:reply, :not_open, s}
  end

  def handle_call(:break_transaction, _from, s) do
    {:reply, :broken, disconnect(s)}
  end

  ## Close transaction

  def handle_call(:close_transaction, _from, %{transaction: :sandbox} = s) do
    {:reply, :closed, %{s | transaction: :closed}}
  end

  def handle_call(:close_transaction, _from, %{transaction: :closed} = s) do
    {:reply, :not_open, s}
  end

  def handle_call(:close_transaction, _from, %{transaction: ref} = s) do
    Process.demonitor(ref, [:flush])
    {:reply, :closed, %{s | transaction: :closed}}
  end

  # Lazy connection handling

  def handle_call(request, from, %{conn: nil, params: params, module: module} = s) do
    case module.connect(params) do
      {:ok, conn}   -> handle_call(request, from, %{s | conn: conn})
      {:error, err} -> {:reply, {:error, err}, s}
    end
  end

  def handle_call(:ask, _from, s) do
    {:reply, {:ok, modconn(s)}, s}
  end

  ## Open transaction

  def handle_call(:open_transaction, _from, %{transaction: :sandbox} = s) do
    {:reply, {:sandbox, modconn(s)}, s}
  end

  def handle_call(:open_transaction, {pid, _}, %{transaction: :closed} = s) do
    ref = Process.monitor(pid)
    {:reply, {:ok, modconn(s)}, %{s | transaction: ref}}
  end

  def handle_call(:open_transaction, from, %{transaction: _old_ref} = s) do
    handle_call(:open_transaction, from, disconnect(s))
  end

  ## Sandbox transaction

  def handle_call(:sandbox_transaction, _from, %{transaction: :sandbox} = s) do
    {:reply, {:sandbox, modconn(s)}, s}
  end

  def handle_call(:sandbox_transaction, _from, %{transaction: :closed} = s) do
    {:reply, {:ok, modconn(s)}, %{s | transaction: :sandbox}}
  end

  def handle_call(:sandbox_transaction, _from, %{transaction: _} = s) do
    {:reply, :already_open, s}
  end

  # The connection crashed. We don't need to notify
  # the client if we have an open transaction because
  # it will fail with noproc anyway. close_transaction
  # and break_transaction witll return :not_open.
  def handle_info({:EXIT, conn, _reason}, %{conn: conn} = s) do
    {:noreply, disconnect(%{s | conn: nil})}
  end

  # The transaction owner crashed without closing.
  def handle_info({:DOWN, ref, _, _, _}, %{transaction: ref} = s) do
    {:noreply, disconnect(%{s | transaction: :closed})}
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

  defp disconnect(%{conn: conn, transaction: ref, module: module} = s) do
    conn && module.disconnect(conn)

    if is_reference(ref) do
      Process.demonitor(ref, [:flush])
    end

    %{s | conn: nil, transaction: :closed}
  end
end
