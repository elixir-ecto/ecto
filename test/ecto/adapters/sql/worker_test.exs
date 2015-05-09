defmodule Ecto.Adapters.SQL.WorkerTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Worker
  alias Ecto.Adapters.SQL.Broker

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

      if opts[:error] do
        {:error, RuntimeError.exception("oops")}
      else
        {:ok, %{}}
      end
    end

    def begin_transaction, do: "BEGIN"
    def rollback, do: "ROLLBACK"
    def commit, do: "COMMIT"
    def savepoint(savepoint), do: "SAVEPOINT " <> savepoint
    def rollback_to_savepoint(savepoint), do: "ROLLBACK TO SAVEPOINT " <> savepoint
  end

  setup %{test: name} = context do
    timeout = :sbroker_time.milli_seconds_to_native(5000)
    queue_spec = {:squeue_timeout, timeout, :out, 1, :drop}
    opts = [client_queue: queue_spec, worker_queue: queue_spec,
      queue_interval: 200, name: name]
    {:ok, broker} = Broker.start_link(opts)
    {:ok, %{broker: broker}}
  end

  @opts [timeout: :infinity]

  test "worker starts without an active connection", %{broker: broker} do
    {:ok, worker} = Worker.start_link({broker, Connection, []})

    assert Process.alive?(worker)
    refute :sys.get_state(worker).conn
  end

  test "worker starts with an active connection", %{broker: broker} do
    {:ok, worker} = Worker.start_link({broker, Connection, lazy: false})

    assert Process.alive?(worker)
    assert :sys.get_state(worker).conn
  end

  test "worker survives, connection stops if caller dies", %{broker: broker} do
    {:ok, worker} = Worker.start({broker, Connection, lazy: false})
    conn       = :sys.get_state(worker).conn
    conn_mon   = Process.monitor(conn)
    worker_mon = Process.monitor(worker)

    spawn_link(fn ->
      _ = Broker.checkout(broker)
    end)

    assert_receive {:DOWN, ^conn_mon, :process, ^conn, _}, 1000
    refute_received {:DOWN, ^worker_mon, :process, ^worker, _}
    refute :sys.get_state(worker).conn
  end

  test "worker survives, caller dies if connection dies", %{broker: broker} do
    {:ok, worker} = Worker.start({broker, Connection, lazy: false})
    conn = :sys.get_state(worker).conn
    parent = self()

    caller = spawn_link(fn ->
      ^worker = Broker.checkout(broker)
      Worker.begin!(worker, @opts)
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
    refute :sys.get_state(worker).conn
  end

  test "worker correctly manages transactions", %{broker: broker} do
    {:ok, worker} = Worker.start({broker, Connection, lazy: false})

    Worker.begin!(worker, @opts)
    Worker.begin!(worker, @opts)
    Worker.rollback!(worker, @opts)
    Worker.commit!(worker, @opts)

    assert commands(worker) ==
           ["BEGIN", "SAVEPOINT ecto_1", "ROLLBACK TO SAVEPOINT ecto_1", "COMMIT"]

    Worker.begin!(worker, @opts)
    Worker.rollback!(worker, @opts)

    assert commands(worker) == ["BEGIN", "ROLLBACK"]
  end

  test "worker replies with error on transaction error", %{broker: broker} do
    {:ok, worker} = Worker.start({broker, Connection, lazy: false})

    Worker.begin!(worker, @opts)

    assert_raise RuntimeError, "oops", fn ->
      Worker.rollback!(worker, Keyword.put(@opts, :error, true))
    end

    refute :sys.get_state(worker).conn
  end

  test "worker correctly manages test transactions", %{broker: broker} do
    {:ok, worker} = Worker.start({broker, Connection, lazy: false})

    # Check for idempotent commands
    Worker.restart_test_transaction!(worker, @opts)
    Worker.rollback_test_transaction!(worker, @opts)
    Worker.begin_test_transaction!(worker, @opts)

    Worker.begin_test_transaction!(worker, @opts)
    Worker.restart_test_transaction!(worker, @opts)
    Worker.rollback_test_transaction!(worker, @opts)

    assert commands(worker) == ["BEGIN", "SAVEPOINT ecto_sandbox",
                                "ROLLBACK TO SAVEPOINT ecto_sandbox", "ROLLBACK"]
  end

  defp commands(worker) do
    conn = :sys.get_state(worker).conn
    Agent.get_and_update(conn, fn commands -> {Enum.reverse(commands), []} end)
  end
end
