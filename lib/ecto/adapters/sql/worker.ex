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

  def link_me(worker) do
    GenServer.cast(worker, {:link, self})
  end

  def unlink_me(worker) do
    GenServer.cast(worker, {:unlink, self})
  end

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

    {:ok, %{conn: conn, params: params, link: nil, transactions: 0, module: module}}
  end

  def handle_cast({:link, pid}, %{link: nil} = s) do
    Process.link(pid)
    {:noreply, %{s | link: pid}}
  end

  def handle_cast({:unlink, pid}, %{link: pid} = s) do
    Process.unlink(pid)
    {:noreply, %{s | link: nil}}
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

  # If there are no transactions, there is no state, so we just ignore the connection crash.
  def handle_info({:EXIT, conn, _reason}, %{conn: conn, transactions: 0} = s) do
    {:noreply, %{s | conn: nil}}
  end

  # If we have a transaction, we need to crash, notifying all interested.
  def handle_info({:EXIT, conn, reason}, %{conn: conn} = s) do
    {:stop, reason, %{s | conn: nil}}
  end

  # If the linked process crashed, assume stale connection and close it.
  def handle_info({:EXIT, link, _reason}, %{conn: conn, link: link, module: module} = s) do
    conn && module.disconnect(conn)
    {:noreply, %{s | link: nil, conn: nil}}
  end

  def handle_info(_info, s) do
    {:noreply, s}
  end

  def terminate(_reason, %{conn: conn, module: module}) do
    conn && module.disconnect(conn)
  end
end
