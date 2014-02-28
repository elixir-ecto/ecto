defmodule Ecto.Adapters.Postgres.Worker do
  @moduledoc false

  use GenServer.Behaviour

  defrecordp :state, [ :conn, :params, :monitor ]

  def start(args) do
    :gen_server.start(__MODULE__, args, [])
  end

  def start_link(args) do
    :gen_server.start_link(__MODULE__, args, [])
  end

  def query!(worker, sql, params \\ []) do
    case :gen_server.call(worker, { :query, sql, params }) do
      { :ok, res } -> res
      { :error, Postgrex.Error[] = err } -> raise err
    end
  end

  def begin!(worker) do
    case :gen_server.call(worker, :begin) do
      :ok -> :ok
      Postgrex.Error[] = err -> raise err
    end
  end

  def commit!(worker) do
    case :gen_server.call(worker, :commit) do
      :ok -> :ok
      Postgrex.Error[] = err -> raise err
    end
  end

  def rollback!(worker) do
    case :gen_server.call(worker, :rollback) do
      :ok -> :ok
      Postgrex.Error[] = err -> raise err
    end
  end

  def monitor_me(worker) do
    :gen_server.cast(worker, { :monitor, self })
  end

  def demonitor_me(worker) do
    :gen_server.cast(worker, { :demonitor, self })
  end

  def init(args) do
    Process.flag(:trap_exit, true)

    conn =
      case args[:lazy] == "false" && Postgrex.Connection.start_link(args) do
        { :ok, conn } -> conn
        _ -> nil
      end

    { :ok, state(conn: conn, params: args) }
  end

  # Connection is disconnected, reconnect before continuing
  def handle_call(request, from, state(conn: nil, params: params) = s) do
    case Postgrex.Connection.start_link(params) do
      { :ok, conn } ->
        handle_call(request, from, state(s, conn: conn))
      { :error, err } ->
        { :reply, { :error, err }, s }
    end
  end

  def handle_call({ :query, sql, params }, _from, state(conn: conn) = s) do
    { :reply, Postgrex.Connection.query(conn, sql, params), s }
  end

  def handle_call(:begin, _from, state(conn: conn) = s) do
    { :reply, Postgrex.Connection.begin(conn), s }
  end

  def handle_call(:commit, _from, state(conn: conn) = s) do
    { :reply, Postgrex.Connection.commit(conn), s }
  end

  def handle_call(:rollback, _from, state(conn: conn) = s) do
    { :reply, Postgrex.Connection.rollback(conn), s }
  end

  def handle_cast({ :monitor, pid }, state(monitor: nil) = s) do
    ref = Process.monitor(pid)
    { :noreply, state(s, monitor: { pid, ref }) }
  end

  def handle_cast({ :demonitor, pid }, state(monitor: { pid, ref }) = s) do
    Process.demonitor(ref)
    { :noreply, state(s, monitor: nil) }
  end

  def handle_info({ :EXIT, conn, _reason }, state(conn: conn) = s) do
    { :noreply, state(s, conn: nil) }
  end

  def handle_info({ :DOWN, ref, :process, pid, _info }, state(monitor: { pid, ref }) = s) do
    { :stop, :normal, s }
  end

  def handle_info(_info, s) do
    { :noreply, s }
  end

  def terminate(_reason, state(conn: nil)) do
    :ok
  end

  def terminate(_reason, state(conn: conn)) do
    Postgrex.Connection.stop(conn)
  end
end
