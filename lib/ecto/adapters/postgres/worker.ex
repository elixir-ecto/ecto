defmodule Ecto.Adapters.Postgres.Worker do
  @moduledoc false

  use GenServer.Behaviour

  defrecordp :state, [ :conn, :params ]

  def start_link(args) do
    :gen_server.start_link __MODULE__, args, []
  end

  def query!(worker, sql) do
    case :gen_server.call(worker, { :query, sql }) do
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

  def init(args) do
    Process.flag(:trap_exit, true)

    conn = case Postgrex.Connection.start_link(args) do
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
        case request do
          { :query, _ } -> { :error, err }
          _ -> err
        end
    end
  end

  def handle_call({ :query, sql }, _from, state(conn: conn) = s) do
    { :reply, Postgrex.Connection.query(conn, sql), s }
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

  def handle_info({ :EXIT, conn, _reason }, state(conn: conn) = s) do
    { :noreply, state(s, conn: nil) }
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
