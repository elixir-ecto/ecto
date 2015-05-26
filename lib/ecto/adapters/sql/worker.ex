defmodule Ecto.Adapters.SQL.Worker do
  @moduledoc false
  use GenServer

  def start_link({module, args}) do
    GenServer.start_link(__MODULE__, {module, args})
  end

  def start({module, args}) do
    GenServer.start(__MODULE__, {module, args})
  end

  def ask(worker, timeout) do
    GenServer.call(worker, :ask, timeout)
  end

  def cancel(worker, timeout) do
    GenServer.call(worker, :cancel, timeout)
  end

  def done(worker, monitor, trans) do
    GenServer.cast(worker, {:done, monitor, trans})
  end

  def stop(worker, monitor, timeout) do
    GenServer.call(worker, {:stop, monitor}, timeout)
  end

  def begin_test_transaction(worker, monitor, trans, opts) do
    call(worker, {:begin_test_transaction, monitor, trans, opts}, opts)
  end

  def restart_test_transaction(worker, monitor, trans, opts) do
    call(worker, {:restart_test_transaction, monitor, trans, opts}, opts)
  end

  def rollback_test_transaction(worker, monitor, trans, opts) do
    call(worker, {:rollback_test_transaction, monitor, trans, opts}, opts)
  end

  defp call(worker, command, opts) do
    GenServer.call(worker, command, opts[:timeout])
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

    {:ok, %{conn: conn, params: params, client: nil, monitor: nil,
            transactions: [], module: module, sandbox: false}}
  end

  def handle_call(:cancel, {client, _}, %{client: client} = s) do
    {:reply, :ok, wipe_state(s)}
  end

  def handle_call(:cancel, _, s) do
    {:reply, :ok, s}
  end

  def handle_call(:ask, from, %{client: nil} = s) do
    handle_ask(from, s)
  end

  def handle_call(:ask, from, %{client: client} = s) do
    # Technically it is possible for poolboy to receive a :DOWN, assign a new
    # client and that client to call ask without the worker being sent a :DOWN.
    # If is_alive?/1 returns true then poolboy can not have been sent a :DOWN
    # and there is a bug.
    if Process.is_alive?(client) do
      {:stop, :busy_ask, s}
    else
      handle_call(:ask, from, wipe_state(s))
    end
  end

  def handle_call({:stop, monitor}, _, %{monitor: monitor} = s) do
    {:reply, :ok, wipe_state(s)}
  end

  def handle_call({:begin_test_transaction, monitor, [sandbox: _] = trans, _}, _from,
  %{monitor: monitor, transactions: trans, sandbox: true} = s) do
    {:reply, {:ok, trans}, s}
  end

  def handle_call({:begin_test_transaction, monitor, [], opts}, _from,
  %{monitor: monitor, transactions: []} = s) do
    case begin_sandbox(%{s | sandbox: true}, opts) do
      {:ok, %{transactions: trans} = s} -> {:reply, {:ok, trans}, s}
      {:error, err}                     -> {:reply, {:error, err}, s}
    end
  end

  def handle_call({:restart_test_transaction, monitor, [], _opts}, _from,
  %{monitor: monitor, transactions: []} = s) do
    {:reply, {:ok, []}, s}
  end

  def handle_call({:restart_test_transaction, monitor, [sandbox: savepoint] = trans, opts}, _from,
  %{monitor: monitor, transactions: trans} = s) do
    %{conn: conn, module: module} = s

    case module.query(conn, module.rollback_to_savepoint(savepoint), [], opts) do
      {:ok, _} -> {:reply, {:ok, trans}, s}
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call({:rollback_test_transaction, monitor, [], _opts}, _from,
  %{monitor: monitor, transactions: []} = s) do
    {:reply, {:ok, []}, s}
  end

  def handle_call({:rollback_test_transaction, monitor, [sandbox: _] = trans, opts}, _from,
  %{monitor: monitor, transactions: trans} = s) do
    %{conn: conn, module: module} = s

    case module.query(conn, module.rollback, [], opts) do
      {:ok, _} ->
        {:reply, {:ok, []}, %{s | transactions: [], sandbox: false}}
      {:error, _} = err ->
        {:reply, err, s}
    end
  end

  def handle_cast({:done, monitor, trans}, %{monitor: monitor, transactions: trans} = s) do
    Process.demonitor(monitor, [:flush])
    {:noreply, %{s | client: nil, monitor: nil}}
  end

  def handle_info({:EXIT, conn, _reason}, %{conn: conn} = s) do
    {:noreply, %{s | conn: nil}}
  end

  def handle_info({:DOWN, monitor, _, _, _}, %{monitor: monitor} = s)
  when is_reference(monitor) do
    {:noreply, wipe_state(s)}
  end

  def handle_info(_info, s) do
    {:noreply, s}
  end

  def terminate(_reason, %{conn: conn, module: module}) do
    conn && module.disconnect(conn)
  end

  ## Helpers

  defp begin_sandbox(%{sandbox: false} = s, _opts), do: {:ok, s}
  defp begin_sandbox(%{sandbox: true} = s, opts) do
    %{conn: conn, module: module} = s

    case module.query(conn, module.begin_transaction, [], opts) do
      {:ok, _} ->
        savepoint = "ecto_sandbox"
        case module.query(conn, module.savepoint(savepoint), [], opts) do
          {:ok, _} ->
            {:ok, %{s | transactions: [sandbox: savepoint]}}
          {:error, _} = err -> err
        end
      {:error, _} = err ->
        err
    end
  end

  defp handle_ask(from, %{conn: nil, params: params, module: module} = s) do
    case module.connect(params) do
      {:ok, conn} ->
        case begin_sandbox(%{s | conn: conn}, params) do
          {:ok, s}      -> handle_ask(from, s)
          {:error, err} -> {:reply, {:error, err}, s}
        end
      {:error, err} ->
        {:reply, {:error, err}, s}
    end
  end
  defp handle_ask({pid, _}, %{module: module, conn: conn, transactions: trans} =s) do
    monitor = Process.monitor(pid)
    reply = {:ok, {module, conn, monitor, trans}}
    {:reply, reply, %{s | client: pid, monitor: monitor}}
  end

  defp wipe_state(%{conn: conn, module: module, monitor: monitor} = s) do
    conn && module.disconnect(conn)

    if monitor, do: Process.demonitor(monitor, [:flush])

    %{s | conn: nil, client: nil, monitor: nil, transactions: []}
  end
end
