if Code.ensure_loaded?(Postgrex.Connection) do
  defmodule Ecto.Adapters.Postgres.Worker do
    @moduledoc false

    use GenServer

    @timeout 5000

    def start(args) do
      :gen_server.start(__MODULE__, args, [])
    end

    def start_link(args) do
      :gen_server.start_link(__MODULE__, args, [])
    end

    def query!(worker, sql, params, opts) do
      case :gen_server.call(worker, {:query, sql, params, opts}, opts[:timeout]) do
        {:ok, res} -> res
        {:error, %Postgrex.Error{} = err} -> raise err
      end
    end

    def begin!(worker, opts) do
      case :gen_server.call(worker, {:begin, opts}, opts[:timeout]) do
        :ok -> :ok
        {:error, %Postgrex.Error{} = err} -> raise err
      end
    end

    def commit!(worker, opts) do
      case :gen_server.call(worker, {:commit, opts}, opts[:timeout]) do
        :ok -> :ok
        {:error, %Postgrex.Error{} = err} -> raise err
      end
    end

    def rollback!(worker, opts) do
      case :gen_server.call(worker, {:rollback, opts}, opts[:timeout]) do
        :ok -> :ok
        {:error, %Postgrex.Error{} = err} -> raise err
      end
    end

    def monitor_me(worker) do
      :gen_server.cast(worker, {:monitor, self})
    end

    def demonitor_me(worker) do
      :gen_server.cast(worker, {:demonitor, self})
    end

    def init(opts) do
      Process.flag(:trap_exit, true)

      eager? = Keyword.get(opts, :lazy, true) in [false, "false"]

      if eager? do
        case Postgrex.Connection.start_link(opts) do
          {:ok, conn} ->
            conn = conn
          _ ->
            :ok
        end
      end

      {:ok, Map.merge(new_state, %{conn: conn, params: opts})}
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

    def handle_call({:begin, opts}, _from, %{conn: conn} = s) do
      {:reply, Postgrex.Connection.begin(conn, opts), s}
    end

    def handle_call({:commit, opts}, _from, %{conn: conn} = s) do
      {:reply, Postgrex.Connection.commit(conn, opts), s}
    end

    def handle_call({:rollback, opts}, _from, %{conn: conn} = s) do
      {:reply, Postgrex.Connection.rollback(conn, opts), s}
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
      {:noreply, %{s | conn: nil}}
    end

    def handle_info({:DOWN, ref, :process, pid, _info}, %{monitor: {pid, ref}} = s) do
      {:stop, :normal, s}
    end

    def handle_info(_info, s) do
      {:noreply, s}
    end

    def terminate(_reason, %{conn: nil}) do
      :ok
    end

    def terminate(_reason, %{conn: conn}) do
      Postgrex.Connection.stop(conn)
    end

    defp new_state do
      %{conn: nil, params: nil, monitor: nil}
    end
  end
end
