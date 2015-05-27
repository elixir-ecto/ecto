defmodule Ecto.Adapters.Worker do
  @moduledoc """
  Defines a worker to be used by adapters.

  The worker is responsible for managing the connection to
  the database, automatically starting a new one if it crashes.
  The `ask/2` and `ask!/2` functions can be used any time to
  retrieve the connection and its module.

  The worker also adds support for laziness, allowing developers
  to create workers but connect to the database only when needed
  for the first time. Finally, the worker also provides transaction
  semantics, with open/close commands as well as a sandbox mode.

  In order to use a worker, adapter developers need to implement
  two callbacks in a module, `connect/1` and `disconnect/1` defined
  in this module. The worker is started by passing the module that
  implements the callbacks and as well as the connection arguments.

  ## Transaction modes

  The worker supports transactions. The idea is that, once a
  transaction is open, the worker is going to monitor the client
  and disconnect if the client crashes without properly closing
  the connection.

  Most of the transaction functions are about telling the worker
  how to react on crashes, the client is still responsible for
  keeping the transaction state.

  The worker also supports a sandbox transaction, which means
  transaction management is done on the client and opening a
  transaction is then disabled.

  Finally, operations like `break_transaction/2` can be used
  when something goes wrong, ensuring a disconnection happens.
  """

  use GenServer
  use Behaviour

  @type modconn :: {module :: atom, conn :: pid}

  @doc """
  Connects to the underlying database.

  Should return a process which is linked to
  the caller process or an error.
  """
  defcallback connect(Keyword.t) :: {:ok, pid} | {:error, term}

  @doc """
  Disconnects the given `pid`.

  If the given `pid` no longer exists, it should not raise.
  """
  defcallback disconnect(pid) :: :ok

  @doc """
  Starts a linked worker for the given module and params.
  """
  def start_link({module, params}) do
    GenServer.start_link(__MODULE__, {module, params})
  end

  @doc """
  Starts a worker for the given module and params.
  """
  def start({module, params}) do
    GenServer.start(__MODULE__, {module, params})
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
  will wipeout all connection state in case of crashes.

  It returns an `:ok` tuple if the transaction can be
  opened, a `:sandbox` tuple in case the transaction
  could not be openned because it is in sandbox mode
  or an `:error` tuple, usually when the adapter is
  unable to connect.

  ## FAQ

  Question: What happens if `open_transaction/2` is
  called when a transaction is already open?

  Answer: If a transaction is already open, the previous
  transaction along side its connection will be discarded
  and a new one will be started transparently. The reasoning
  is that if the client is calling `open_transaction/2` when
  one is already open, is because the client lost its state,
  and we should treat it transparently by disconnecting the
  old state and starting a new one.
  """
  @spec open_transaction(pid, timeout) :: {:ok, modconn} | {:sandbox, modconn} | {:error, Exception.t}
  def open_transaction(worker, timeout) do
    GenServer.call(worker, :open_transaction, timeout)
  end

  @doc """
  Closes a transaction.

  Both sandbox and open transactions can be closed.
  Returns `:not_open` if a transaction was not open.
  """
  @spec close_transaction(pid, timeout) :: :not_open | :closed
  def close_transaction(worker, timeout) do
    GenServer.call(worker, :close_transaction, timeout)
  end

  @doc """
  Breaks a transaction.

  Automatically forces the worker to disconnect unless
  in sandbox mode. Returns `:not_open` if a transaction
  was not open.
  """
  @spec break_transaction(pid, timeout) :: :broken | :not_open | :sandbox
  def break_transaction(worker, timeout) do
    GenServer.call(worker, :break_transaction, timeout)
  end

  @doc """
  Starts a sandbox transaction.

  A sandbox transaction is not monitored by the worker.
  This functions returns an `:ok` tuple in case a sandbox
  transaction has started, a `:sandbox` tuple if it was
  already in sandbox mode or `:already_open` if it was
  previously open.
  """
  @spec sandbox_transaction(pid, timeout) :: {:ok, modconn} | {:sandbox, modconn} | :already_open
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

  ## Lazy connection handling

  def handle_call(request, from, %{conn: nil, params: params, module: module} = s) do
    case module.connect(params) do
      {:ok, conn}   -> handle_call(request, from, %{s | conn: conn})
      {:error, err} -> {:reply, {:error, err}, s}
    end
  end

  ## Ask

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

  ## Info

  # The connection crashed. We don't need to notify
  # the client if we have an open transaction because
  # it will fail with noproc anyway. close_transaction
  # and break_transaction will return :not_open after this.
  def handle_info({:EXIT, conn, _reason}, %{conn: conn} = s) do
    {:noreply, disconnect(%{s | conn: nil})}
  end

  # The transaction owner crashed without closing.
  # We need to assume we don't know the connection state.
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
