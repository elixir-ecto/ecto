defmodule Ecto.Adapters.SQL.WorkerTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Worker

  defmodule Connection do
    def connect(_opts) do
      Agent.start_link(fn -> end)
    end

    def disconnect(conn) do
      Agent.stop(conn)
    end

    def query(conn, _, [], opts) do
      Agent.get(conn, fn _ ->
        {:ok, []}
      end, opts[:timeout])
    end

    def query(conn, "sleep", [value], opts) do
      Agent.get(conn, fn _ ->
        :timer.sleep(value)
        {:ok, []}
      end, opts[:timeout])
    end
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
      Worker.query!(worker, "sleep", [0], timeout: 5000)
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

  test "worker dies if connection dies inside of transaction" do
    {:ok, worker} = Worker.start({Connection, lazy: false})
    conn = :sys.get_state(worker).conn
    conn_mon   = Process.monitor(conn)
    worker_mon = Process.monitor(worker)

    Worker.begin!(worker, [timeout: :infinity])
    Process.exit(conn, :shutdown)

    assert_receive {:DOWN, ^conn_mon, :process, ^conn, _}, 1000
    assert_receive {:DOWN, ^worker_mon, :process, ^worker, _}, 1000
  end
end
