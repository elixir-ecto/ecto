defmodule Ecto.Adapters.SQL.WorkerTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Worker

  defmodule Connection do
    def connect(_opts) do
      Agent.start_link(fn -> [] end)
    end

    def disconnect(conn) do
      Agent.stop(conn)
    end

    def query(conn, "sleep", [value], opts) do
      Agent.get(conn, fn _ ->
        :timer.sleep(value)
        {:ok, %{}}
      end, opts[:timeout])
    end

    def query(conn, query, [], opts) do
      Agent.update(conn, &[query|&1], opts[:timeout])
      {:ok, %{}}
    end

    def begin_transaction, do: "BEGIN"
    def rollback, do: "ROLLBACK"
    def commit, do: "COMMIT"
    def savepoint(savepoint), do: "SAVEPOINT " <> savepoint
    def rollback_to_savepoint(savepoint), do: "ROLLBACK TO SAVEPOINT " <> savepoint
  end

  test "worker starts without an active connection" do
    {:ok, worker} = Worker.start_link({Connection, []})

    assert Process.alive?(worker)
    refute :sys.get_state(worker).conn
  end

  test "worker starts with an active connection" do
    {:ok, worker} = Worker.start_link({Connection, lazy: false})

    assert Process.alive?(worker)
    assert :sys.get_state(worker).conn
  end

  test "worker survives, connection stops if caller dies" do
    {:ok, worker} = Worker.start({Connection, lazy: false})
    conn = :sys.get_state(worker).conn
    conn_mon   = Process.monitor(conn)
    worker_mon = Process.monitor(worker)

    spawn_link(fn ->
      Worker.link_me(worker)
    end)

    assert_receive {:DOWN, ^conn_mon, :process, ^conn, _}, 1000
    refute_received {:DOWN, ^worker_mon, :process, ^worker, _}
    refute :sys.get_state(worker).conn
  end

  test "worker survives if connection dies outside of transaction" do
    {:ok, worker} = Worker.start({Connection, lazy: false})
    conn = :sys.get_state(worker).conn
    conn_mon   = Process.monitor(conn)
    worker_mon = Process.monitor(worker)

    Process.exit(conn, :shutdown)

    assert_receive {:DOWN, ^conn_mon, :process, ^conn, _}, 1000
    refute_received {:DOWN, ^worker_mon, :process, ^worker, _}
    refute :sys.get_state(worker).conn
  end

  test "worker survives, caller dies if connection dies inside of transaction" do
    {:ok, worker} = Worker.start({Connection, lazy: false})
    conn = :sys.get_state(worker).conn
    parent = self()

    caller = spawn_link(fn ->
      Worker.link_me(worker)
      Worker.begin!(worker, [timeout: :infinity])
      send parent, :go_on
      :timer.sleep(:infinity)
    end)

    # Wait until caller is linked
    assert_receive :go_on, :infinity
    Process.unlink(caller)

    conn_mon   = Process.monitor(conn)
    caller_mon = Process.monitor(caller)
    worker_mon = Process.monitor(worker)
    Process.exit(conn, :shutdown)

    assert_receive {:DOWN, ^conn_mon, :process, ^conn, _}, 1000
    assert_receive {:DOWN, ^caller_mon, :process, ^caller, _}, 1000
    refute_received {:DOWN, ^worker_mon, :process, ^worker, _}
  end

  test "worker correctly manages transactions" do
    {:ok, worker} = Worker.start({Connection, lazy: false})

    Worker.begin!(worker, [timeout: :infinity])
    Worker.begin!(worker, [timeout: :infinity])
    Worker.rollback!(worker, [timeout: :infinity])
    Worker.commit!(worker, [timeout: :infinity])

    assert commands(worker) ==
           ["BEGIN", "SAVEPOINT ecto_1", "ROLLBACK TO SAVEPOINT ecto_1", "COMMIT"]

    Worker.begin!(worker, [timeout: :infinity])
    Worker.rollback!(worker, [timeout: :infinity])

    assert commands(worker) == ["BEGIN", "ROLLBACK"]
  end

  defp commands(worker) do
    conn = :sys.get_state(worker).conn
    Agent.get_and_update(conn, fn commands -> {Enum.reverse(commands), []} end)
  end
end
