defmodule Ecto.Adapters.SQL.Worker do
  @moduledoc false
  use GenServer

  def start_link({module, args}) do
    GenServer.start_link(__MODULE__, {module, args})
  end

  def start({module, args}) do
    GenServer.start(__MODULE__, {module, args})
  end

  def link_me(worker, timeout) do
    GenServer.call(worker, :link_me, timeout)
  end

  def unlink_me(worker, timeout) do
    GenServer.call(worker, :unlink_me, timeout)
  end

  def query!(worker, sql, params, opts) do
    case GenServer.call(worker, :query, opts[:timeout]) do
      {:ok, {module, conn}} ->
        case module.query(conn, sql, params, opts) do
          {:ok, res} -> res
          {:error, err} -> raise err
        end
      {:error, err} ->
        raise err
    end
  end

  def begin!(worker, opts) do
    call!(worker, {:begin, opts}, opts)
  end

  def commit!(worker, opts) do
    call!(worker, {:commit, opts}, opts)
  end

  def rollback!(worker, opts) do
    call!(worker, {:rollback, opts}, opts)
  end

  def begin_test_transaction!(worker, opts) do
    call!(worker, {:begin_test_transaction, opts}, opts)
  end

  def restart_test_transaction!(worker, opts) do
    call!(worker, {:restart_test_transaction, opts}, opts)
  end

  def rollback_test_transaction!(worker, opts) do
    call!(worker, {:rollback_test_transaction, opts}, opts)
  end

  defp call!(worker, command, opts) do
    case GenServer.call(worker, command, opts[:timeout]) do
      :ok -> :ok
      {:error, err} -> raise err
    end
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

    {:ok, %{conn: conn, params: params, link: nil,
            transactions: 0, module: module, sandbox: false}}
  end

  # Those functions do not need a connection
  def handle_call(:link_me, {pid, _}, %{link: nil} = s) do
    Process.link(pid)
    {:reply, :ok, %{s | link: pid}}
  end

  def handle_call(:unlink_me, {pid, _}, %{link: pid} = s) do
    Process.unlink(pid)
    {:reply, :ok, %{s | link: nil}}
  end

  # Connection is disconnected, reconnect before continuing
  def handle_call(request, from, %{conn: nil, params: params, module: module} = s) do
    case module.connect(params) do
      {:ok, conn} ->
        case begin_sandbox(%{s | conn: conn}, params) do
          {:ok, s}      -> handle_call(request, from, s)
          {:error, err} -> {:reply, {:error, err}, s}
        end
      {:error, err} ->
        {:reply, {:error, err}, s}
    end
  end

  def handle_call(:query, _from, %{conn: conn, module: module} = s) do
    {:reply, {:ok, {module, conn}}, s}
  end

  def handle_call({:begin, opts}, _from, s) do
    %{conn: conn, transactions: trans, module: module} = s

    sql =
      if trans == 0 do
        module.begin_transaction
      else
        module.savepoint "ecto_#{trans}"
      end

    # Increase the transaction counter as rollback should be triggered.
    s = %{s | transactions: trans + 1}

    case module.query(conn, sql, [], opts) do
      {:ok, _} ->
        {:reply, :ok, s}
      {:error, _} = err ->
        {:reply, err, s}
    end
  end

  def handle_call({:commit, opts}, _from, %{transactions: trans} = s) when trans >= 1 do
    %{conn: conn, module: module} = s

    reply =
      case trans do
        1 -> module.query(conn, module.commit, [], opts)
        _ -> {:ok, %{}}
      end

    case reply do
      {:ok, _} ->
        {:reply, :ok, %{s | transactions: trans - 1}}
      {:error, _} = err ->
        # Don't change the transaction counter as rollback should be triggered.
        {:reply, err, s}
    end
  end

  def handle_call({:rollback, opts}, _from, %{transactions: trans} = s) when trans >= 1 do
    %{conn: conn, module: module} = s

    sql =
      case trans do
        1 -> module.rollback
        _ -> module.rollback_to_savepoint "ecto_#{trans-1}"
      end

    # Always reduce the transaction counter as the user
    # will exit the transaction block anyway.
    s = %{s | transactions: trans - 1}

    case module.query(conn, sql, [], opts) do
      {:ok, _} ->
        {:reply, :ok, s}
      {:error, _} = err when trans == 1 ->
        # We don't know if we actually rolled back, so it is best
        # to completely drop the connection.
        #
        # In any case, we don't need to worry about the client as
        # it should not expect any state in the connection anyway.
        module.disconnect(conn)
        {:reply, err, %{s | conn: nil}}
      {:error, _} = err ->
        {:reply, err, s}
    end
  end

  def handle_call({:begin_test_transaction, _opts}, _from, %{sandbox: true} = s) do
    {:reply, :ok, s}
  end

  def handle_call({:begin_test_transaction, opts}, _from, %{transactions: 0} = s) do
    case begin_sandbox(%{s | sandbox: true}, opts) do
      {:ok, s}      -> {:reply, :ok, s}
      {:error, err} -> {:reply, {:error, err}, s}
    end
  end

  def handle_call({:restart_test_transaction, _opts}, _from, %{sandbox: false} = s) do
    {:reply, :ok, s}
  end

  def handle_call({:restart_test_transaction, opts}, _from, %{transactions: 1} = s) do
    %{conn: conn, module: module} = s

    case module.query(conn, module.rollback_to_savepoint("ecto_sandbox"), [], opts) do
      {:ok, _} -> {:reply, :ok, s}
      {:error, _} = err -> {:reply, err, s}
    end
  end

  def handle_call({:rollback_test_transaction, _opts}, _from, %{sandbox: false} = s) do
    {:reply, :ok, s}
  end

  def handle_call({:rollback_test_transaction, opts}, _from, %{transactions: 1} = s) do
    %{conn: conn, module: module} = s

    case module.query(conn, module.rollback, [], opts) do
      {:ok, _} ->
        {:reply, :ok, %{s | transactions: 0, sandbox: false}}
      {:error, _} = err ->
        {:reply, err, s}
    end
  end

  # The connection crashed, notify all linked process.
  def handle_info({:EXIT, conn, _reason}, %{conn: conn} = s) do
    wipe_state(%{s | conn: nil})
  end

  # If a linked process crashed, assume stale connection and close it.
  def handle_info({:EXIT, link, _reason}, %{link: link} = s) do
    wipe_state(s)
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
        case module.query(conn, module.savepoint("ecto_sandbox"), [], opts) do
          {:ok, _}          -> {:ok, %{s | transactions: 1}}
          {:error, _} = err -> err
        end
      {:error, _} = err ->
        err
    end
  end

  # Imagine the following scenario:
  #
  #   1. PID starts a transaction
  #   2. PID sends a query
  #   3. The connection crashes (and we receive an EXIT message)
  #
  # If 2 and 3 happen at the same, there is no guarantee which
  # one will be handled first. That's why we can't simply kill
  # the linked processes and start a new connection as we may
  # have left-over messages in the inbox.
  #
  # So this is what we do:
  #
  #   1. We disconnect from the database
  #   2. We kill the linked processes (transaction owner)
  #   3. We remove all calls from that process
  #
  # Because this worker only accept calls and it is controlled by
  # the pool, the expectation is that the number of messages to
  # be removed will always be maximum 1.
  defp wipe_state(%{conn: conn, module: module, link: link} = s) do
    conn && module.disconnect(conn)

    if link do
      Process.unlink(link)
      Process.exit(link, {:ecto, :no_connection})
      clear_calls(link)
    end

    {:noreply, %{s | conn: nil, link: nil, transactions: 0}}
  end

  defp clear_calls(link) do
    receive do
      {:"$gen_call", {^link, _}, _} -> clear_calls(link)
    after
      0 -> :ok
    end
  end
end
