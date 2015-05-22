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

  @opts [timeout: :infinity]

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
    conn       = :sys.get_state(worker).conn
    conn_mon   = Process.monitor(conn)
    worker_mon = Process.monitor(worker)

    spawn_link(fn ->
      Worker.ask(worker, :infinity)
    end)

    assert_receive {:DOWN, ^conn_mon, :process, ^conn, _}, 1000
    refute_received {:DOWN, ^worker_mon, :process, ^worker, _}
    refute :sys.get_state(worker).conn
  end

  test "worker correctly manages test transactions" do
    {:ok, worker} = Worker.start({Connection, lazy: false})

    {:ok, {_, _, monitor, []}} = Worker.ask(worker, :infinity)

    # Check for idempotent commands
    assert Worker.restart_test_transaction(worker, monitor, [], @opts) == {:ok, []}
    assert Worker.rollback_test_transaction(worker, monitor, [], @opts) == {:ok, []}
    assert Worker.begin_test_transaction(worker, monitor, [], @opts) == {:ok, [sandbox: "ecto_sandbox"]}

    assert Worker.begin_test_transaction(worker, monitor, [sandbox: "ecto_sandbox"], @opts) == {:ok, [sandbox: "ecto_sandbox"]}
    assert Worker.begin_test_transaction(worker, monitor, [sandbox: "ecto_sandbox"], @opts) == {:ok, [sandbox: "ecto_sandbox"]}
    assert Worker.restart_test_transaction(worker, monitor, [sandbox: "ecto_sandbox"], @opts) == {:ok, [sandbox: "ecto_sandbox"]}
    assert Worker.rollback_test_transaction(worker, monitor, [sandbox: "ecto_sandbox"], @opts) == {:ok, []}

    assert commands(worker) == ["BEGIN", "SAVEPOINT ecto_sandbox",
                                "ROLLBACK TO SAVEPOINT ecto_sandbox", "ROLLBACK"]
  end

  defp commands(worker) do
    conn = :sys.get_state(worker).conn
    Agent.get_and_update(conn, fn commands -> {Enum.reverse(commands), []} end)
  end
end
