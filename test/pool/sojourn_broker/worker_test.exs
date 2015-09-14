defmodule Ecto.Pools.SojournBroker.WorkerTest do
  use ExUnit.Case, async: true

  alias Ecto.TestPool
  alias Ecto.TestPool.Connection

  @timeout :infinity

  setup context do
    case = context[:case]
    test = context[:test]
    {:ok, [pool: Module.concat(case, test)]}
  end

  test "worker starts without an active connection but connects on go", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([pool_name: pool, lazy: true])
    assert {:go, _, {worker, :lazy}, _, _} = :sbroker.ask(pool, {:run, self()})
    assert Process.alive?(worker)
    conn = :sys.get_state(worker).conn
    assert Process.alive?(conn)
  end

  test "worker starts with an active connection", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([pool_name: pool, lazy: false])
    assert {:go, _, {worker, {Connection, conn}}, _, _} =
      :sbroker.ask(pool, {:run, self()})
    assert Process.alive?(worker)
    assert :sys.get_state(worker).conn == conn
    assert Process.alive?(conn)
  end

  test "worker restarts connection when waiting", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([pool_name: pool])

    conn1 = TestPool.transaction(pool, @timeout,
      fn(:opened, _ref, {Connection, conn}, _) ->
        conn
      end)

    await_len_r(pool, 1)

    ref = Process.monitor(conn1)
    Process.exit(conn1, :kill)
    receive do: ({:DOWN, ^ref, _, _, _} -> :ok)

    await_len_r(pool, 0)

    conn2 = TestPool.transaction(pool, @timeout,
      fn(:opened, _ref, {Connection, conn}, _) ->
        conn
      end)

    assert conn1 != conn2
  end

  test "worker restarts connection after cancel fails", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([pool_name: pool, size: 1, lazy: false])

    conn1 = TestPool.transaction(pool, @timeout,
      fn(:opened, _ref, {Connection, conn}, _) ->
        conn
      end)

    await_len_r(pool, 1)

    {:links, [worker]} = Process.info(conn1, :links)
    :ok = :sys.suspend(worker)
    ref = Process.monitor(conn1)
    Process.exit(conn1, :kill)
    receive do: ({:DOWN, ^ref, _, _, _} -> :ok)

    conn2 = TestPool.transaction(pool, @timeout,
      fn(:opened, _ref, {Connection, conn}, _) ->
        :sys.resume(worker)
        conn
      end)

    assert conn1 == conn2

    conn3 = TestPool.transaction(pool, @timeout,
      fn(:opened, _ref, {Connection, conn}, _) ->
        conn
      end)

    assert conn2 != conn3
  end

  defp await_len_r(pool, len) do
    case :sbroker.len_r(pool, @timeout) do
      ^len -> :ok
      _    -> await_len_r(pool, len)
    end
  end
end
