defmodule Ecto.Adapters.SQL.Worker do
  @moduledoc false
  use GenServer

  def start_link({module, args}) do
    GenServer.start_link(__MODULE__, {module, args})
  end

  def start({module, args}) do
    GenServer.start(__MODULE__, {module, args})
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
    case GenServer.call(worker, {:begin, opts}, opts[:timeout]) do
      :ok -> :ok
      {:error, err} -> raise err
    end
  end

  def commit!(worker, opts) do
    case GenServer.call(worker, {:commit, opts}, opts[:timeout]) do
      :ok -> :ok
      {:error, err} -> raise err
    end
  end

  def rollback!(worker, opts) do
    case GenServer.call(worker, {:rollback, opts}, opts[:timeout]) do
      :ok -> :ok
      {:error, err} -> raise err
    end
  end

  def rollback_pending!(worker, opts) do
    case GenServer.call(worker, {:rollback_pending, opts}, opts[:timeout]) do
      :ok -> :ok
      {:error, err} -> raise err
    end
  end

  def link_me(worker) do
    GenServer.call(worker, :link_me)
  end

  def unlink_me(worker) do
    GenServer.call(worker, :unlink_me)
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

    {:ok, %{conn: conn, params: params, links: HashSet.new, transactions: 0, module: module}}
  end

  def handle_call(:link_me, {pid, _}, %{links: links} = s) do
    Process.link(pid)
    {:reply, :ok, %{s | links: HashSet.put(links, pid)}}
  end

  def handle_call(:unlink_me, {pid, _}, %{links: links} = s) do
    Process.unlink(pid)
    {:reply, :ok, %{s | links: HashSet.delete(links, pid)}}
  end

  # Connection is disconnected, reconnect before continuing
  def handle_call(request, from, %{conn: nil, params: params, module: module} = s) do
    case module.connect(params) do
      {:ok, conn} ->
        handle_call(request, from, %{s | conn: conn})
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

    case module.query(conn, sql, [], opts) do
      {:ok, _} ->
        {:reply, :ok, %{s | transactions: trans + 1}}
      {:error, _} = err ->
        {:stop, err, err, s}
    end
  end

  def handle_call({:commit, opts}, _from, %{transactions: trans} = s) when trans >= 1 do
    %{conn: conn, module: module} = s

    reply =
      case trans do
        1 -> module.query(conn, module.commit, [], opts)
        _ -> {:ok, {[], 0}}
      end

    case reply do
      {:ok, _} ->
        {:reply, :ok, %{s | transactions: trans - 1}}
      {:error, _} = err ->
        {:stop, err, err, s}
    end
  end

  def handle_call({:rollback, opts}, _from, %{transactions: trans} = s) when trans >= 1 do
    %{conn: conn, module: module} = s

    sql =
      case trans do
        1 -> module.rollback
        _ -> module.rollback_to_savepoint "ecto_#{trans-1}"
      end

    case module.query(conn, sql, [], opts) do
      {:ok, _} ->
        {:reply, :ok, %{s | transactions: trans - 1}}
      {:error, _} = err ->
        {:stop, err, err, s}
    end
  end

  def handle_call({:rollback_pending, _opts}, _from, %{transactions: 0} = s) do
    {:reply, :ok, s}
  end

  def handle_call({:rollback_pending, opts}, from, s) do
    handle_call({:rollback, opts}, from, s)
  end

  # The connection crashed, notify all linked process.
  def handle_info({:EXIT, conn, _reason}, %{conn: conn, links: links} = s) do
    kill_links_and_clear_calls(links)
    {:noreply, %{s | conn: nil, links: HashSet.new, transactions: 0}}
  end

  # If a linked process crashed, assume stale connection and close it.
  def handle_info({:EXIT, _link, _reason}, %{conn: conn, module: module, links: links} = s) do
    kill_links_and_clear_calls(links)
    conn && module.disconnect(conn)
    {:noreply, %{s | conn: nil, links: HashSet.new, transactions: 0}}
  end

  def handle_info(_info, s) do
    {:noreply, s}
  end

  def terminate(_reason, %{conn: conn, module: module}) do
    conn && module.disconnect(conn)
  end

  # Imagine the following scenario:
  #
  #   1. PID starts a transaction
  #   2. PID sends a query
  #   3. The connection crashes (and we receive an EXIT message)
  #
  # If 2 and 3 happen at the same, there is no guarantee which
  # one will happen first. That's why we can't simply kill the
  # linked processes and start a new connection as we may have
  # left-over messages in the inbox.
  #
  # So this is what we do:
  #
  #   1. We insert an all_clear marker in the inbox
  #   2. We kill all linked processes (transaction owners)
  #   3. We remove all calls until we get the marker
  #
  # Because this worker only accept calls and it is controlled by
  # the pool, the expectation is that the number of messages to
  # be removed will always be maximum 1.
  defp kill_links_and_clear_calls(links) do
    send self(), :all_clear
    Enum.each links, &Process.exit(&1, {:ecto, :no_connection})
    clear_calls()
  end

  defp clear_calls() do
    receive do
      :all_clear -> :ok
      {:"$gen_call", _, _} -> clear_calls()
    end
  end
end
