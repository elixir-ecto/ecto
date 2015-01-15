if Code.ensure_loaded?(Postgrex.Connection) do
  defmodule Ecto.Adapters.Postgres.Worker do
    @moduledoc false

    use GenServer

    def start(args) do
      GenServer.start(__MODULE__, args)
    end

    def start_link(args) do
      GenServer.start_link(__MODULE__, args)
    end

    def query!(worker, sql, params, opts) do
      case GenServer.call(worker, {:query, sql, params, opts}, opts[:timeout]) do
        {:ok, res} -> res
        {:error, %Postgrex.Error{} = err} -> raise err
      end
    end

    def begin!(worker, opts) do
      case GenServer.call(worker, {:begin, opts}, opts[:timeout]) do
        :ok -> :ok
        {:error, %Postgrex.Error{} = err} -> raise err
      end
    end

    def commit!(worker, opts) do
      case GenServer.call(worker, {:commit, opts}, opts[:timeout]) do
        :ok -> :ok
        {:error, %Postgrex.Error{} = err} -> raise err
      end
    end

    def rollback!(worker, opts) do
      case GenServer.call(worker, {:rollback, opts}, opts[:timeout]) do
        :ok -> :ok
        {:error, %Postgrex.Error{} = err} -> raise err
      end
    end

    def monitor_me(worker) do
      GenServer.cast(worker, {:monitor, self})
    end

    def demonitor_me(worker) do
      GenServer.cast(worker, {:demonitor, self})
    end

    def init(opts) do
      Process.flag(:trap_exit, true)
      lazy? = Keyword.get(opts, :lazy, true)

      unless lazy? do
        case Postgrex.Connection.start_link(opts) do
          {:ok, conn} ->
            conn = conn
          _ ->
            :ok
        end
      end

      {:ok, %{conn: conn, params: opts, monitor: nil, transactions: 0}}
    end

    # Connection is disconnected, reconnect before continuing
    def handle_call(request, from, %{conn: nil, params: params} = s) do
      case Postgrex.Connection.start_link(params) do
        {:ok, conn} ->
          handle_call(request, from, %{s | conn: conn})
        {:error, err} ->
          {:reply, {:error, err}, s}
      end
    end

    def handle_call({:query, sql, params, opts}, _from, %{conn: conn} = s) do
      {:reply, Postgrex.Connection.query(conn, sql, params, opts), s}
    end

    def handle_call({:begin, opts}, _from, %{conn: conn, transactions: trans} = s) do
      sql =
        if trans == 0 do
          "BEGIN"
        else
          "SAVEPOINT ecto_#{trans}"
        end

      reply =
        case Postgrex.Connection.query(conn, sql, [], opts) do
          {:ok, _}          -> :ok
          {:error, _} = err -> err
        end

      {:reply, reply, %{s | transactions: trans + 1}}
    end

    def handle_call({:commit, opts}, _from, %{conn: conn, transactions: trans} = s) when trans >= 1 do
      reply =
        case trans do
          1 ->
            case Postgrex.Connection.query(conn, "COMMIT", [], opts) do
              {:ok, _}          -> :ok
              {:error, _} = err -> err
            end
          _ ->
            :ok
        end

      {:reply, reply, %{s | transactions: trans - 1}}
    end

    def handle_call({:rollback, opts}, _from, %{conn: conn, transactions: trans} = s) when trans >= 1 do
      sql =
        case trans do
          1 -> "ROLLBACK"
          _ -> "ROLLBACK TO SAVEPOINT ecto_#{trans-1}"
        end

      reply =
        case Postgrex.Connection.query(conn, sql, [], opts) do
          {:ok, _}          -> :ok
          {:error, _} = err -> err
        end

      {:reply, reply, %{s | transactions: trans - 1}}
    end

    def handle_cast({:monitor, pid}, %{monitor: nil} = s) do
      ref = Process.monitor(pid)
      {:noreply, %{s | monitor: {pid, ref}}}
    end

    def handle_cast({:demonitor, pid}, %{monitor: {pid, ref}} = s) do
      Process.demonitor(ref)
      {:noreply, %{s | monitor: nil}}
    end

    def handle_info({:EXIT, conn, _reason}, %{conn: conn} = s) do
      {:stop, :normal, %{s | conn: nil}}
    end

    def handle_info({:DOWN, ref, :process, pid, _info}, %{monitor: {pid, ref}} = s) do
      {:stop, :normal, s}
    end

    def handle_info(_info, s) do
      {:noreply, s}
    end

    def terminate(_reason, %{conn: conn}) do
      if conn && Process.alive?(conn) do
        Postgrex.Connection.stop(conn)
      end
    end
  end
end
