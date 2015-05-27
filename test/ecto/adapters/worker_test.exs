defmodule Ecto.Adapters.WorkerTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.Worker

  defmodule Connection do
    def connect(_opts) do
      Agent.start_link(fn -> [] end)
    end

    def disconnect(conn) do
      Agent.stop(conn)
    end
  end

  @timeout :infinity

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

  test "worker cleans up the connection when it crashes" do
    {:ok, worker} = Worker.start_link({Connection, lazy: false})

    {_mod, conn1} = Worker.ask!(worker, @timeout)
    Process.exit(conn1, :kill)
    ref = Process.monitor(conn1)
    receive do: ({:DOWN, ^ref, _, _, _} -> :ok)
    {_mod, conn2} = Worker.ask!(worker, @timeout)

    assert conn1 != conn2
    refute Process.alive?(conn1)
    assert Process.alive?(conn2)
  end

  ## Break transaction

  test "break_transaction does not start a connection on lazy mode" do
    {:ok, worker} = Worker.start_link({Connection, []})
    assert :not_open = Worker.break_transaction(worker, @timeout)
    refute :sys.get_state(worker).conn
  end

  ## Close transaction

  test "close_transaction does not start a connection on lazy mode" do
    {:ok, worker} = Worker.start_link({Connection, []})
    assert :not_open = Worker.close_transaction(worker, @timeout)
    refute :sys.get_state(worker).conn
  end

  ## Open transaction

  test "open_transaction starts a connection on lazy mode" do
    {:ok, worker} = Worker.start_link({Connection, []})
    assert {:ok, {Connection, conn}} = Worker.open_transaction(worker, @timeout)
    assert Process.alive?(conn)
  end

  test "open_transaction can be closed" do
    {:ok, worker} = Worker.start_link({Connection, []})
    Worker.open_transaction(worker, @timeout)
    assert :closed = Worker.close_transaction(worker, @timeout)
  end

  test "open_transaction returns :sandbox when already in sandbox" do
    {:ok, worker} = Worker.start_link({Connection, []})
    Worker.sandbox_transaction(worker, @timeout)
    assert {:sandbox, {Connection, _}} = Worker.open_transaction(worker, @timeout)
  end

  test "open_transaction disconnects when already open" do
    {:ok, worker} = Worker.start_link({Connection, []})
    assert {:ok, {Connection, conn1}} = Worker.open_transaction(worker, @timeout)
    assert {:ok, {Connection, conn2}} = Worker.open_transaction(worker, @timeout)
    assert conn1 != conn2
    refute Process.alive?(conn1)
    assert Process.alive?(conn2)
  end

  test "open_transaction disconnects if caller dies" do
    {:ok, worker} = Worker.start_link({Connection, []})
    {_mod, conn1} = Worker.ask!(worker, @timeout)
    complete_task(fn -> Worker.open_transaction(worker, @timeout) end)

    assert {:ok, {Connection, conn2}} = Worker.open_transaction(worker, @timeout)
    assert conn1 != conn2
    refute Process.alive?(conn1)
    assert Process.alive?(conn2)
  end

  test "open_transaction does not disconnect if caller dies after closing" do
    {:ok, worker} = Worker.start_link({Connection, []})
    {_mod, conn1} = Worker.ask!(worker, @timeout)

    complete_task(fn ->
      Worker.open_transaction(worker, @timeout)
      Worker.close_transaction(worker, @timeout)
    end)

    assert {:ok, {Connection, conn2}} = Worker.open_transaction(worker, @timeout)
    assert conn1 == conn2
    assert Process.alive?(conn1)
  end

  ## Sandbox transaction

  test "sandbox_transaction starts a connection on lazy mode" do
    {:ok, worker} = Worker.start_link({Connection, []})
    assert {:ok, {Connection, conn}} = Worker.sandbox_transaction(worker, @timeout)
    assert Process.alive?(conn)
  end

  test "sandbox_transaction returns :sandbox when already in sandbox" do
    {:ok, worker} = Worker.start_link({Connection, []})
    Worker.sandbox_transaction(worker, @timeout)
    assert {:sandbox, {Connection, _}} = Worker.sandbox_transaction(worker, @timeout)
  end

  test "sandbox_transaction returns :already_open when already open" do
    {:ok, worker} = Worker.start_link({Connection, []})
    Worker.open_transaction(worker, @timeout)
    assert :already_open = Worker.sandbox_transaction(worker, @timeout)
  end

  test "sandbox_transaction can be closed" do
    {:ok, worker} = Worker.start_link({Connection, []})
    Worker.sandbox_transaction(worker, @timeout)
    assert :closed = Worker.close_transaction(worker, @timeout)
  end

  test "sandbox_transaction doesn't care if caller dies" do
    {:ok, worker} = Worker.start_link({Connection, []})
    complete_task(fn -> Worker.sandbox_transaction(worker, @timeout) end)
    assert {:sandbox, {Connection, _}} = Worker.sandbox_transaction(worker, @timeout)
  end

  defp complete_task(fun) do
    {:ok, pid} = Task.start_link(fun)
    ref = Process.monitor(pid)
    receive do: ({:DOWN, ^ref, _, _, _} -> :ok)
  end
end
