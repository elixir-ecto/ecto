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
      conn = GenServer.call(worker, :conn, opts[:timeout])

      case Postgrex.Connection.query(conn, sql, params, opts) do
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

    def link_me(worker) do
      GenServer.cast(worker, {:link, self})
    end

    def unlink_me(worker) do
      GenServer.cast(worker, {:unlink, self})
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

      {:ok, %{conn: conn, params: opts, link: nil, transactions: 0}}
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

    def handle_call(:conn, _from, %{conn: conn} = s) do
      {:reply, conn, s}
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

    def handle_cast({:link, pid}, %{link: nil} = s) do
      Process.link(pid)
      {:noreply, %{s | link: pid}}
    end

    def handle_cast({:unlink, pid}, %{link: pid} = s) do
      Process.unlink(pid)
      {:noreply, %{s | link: nil}}
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
    def handle_info({:EXIT, link, reason}, %{conn: conn, link: link} = s) do
      close_connection(conn)
      {:noreply, %{s | link: nil, conn: nil}}
    end

    def handle_info(_info, s) do
      {:noreply, s}
    end

    def terminate(_reason, %{conn: conn}) do
      close_connection(conn)
    end

    defp close_connection(conn) do
      try do
        conn && Postgrex.Connection.stop(conn)
      catch
        :exit, {:noproc, _} -> :ok
      end
    end
  end
end
