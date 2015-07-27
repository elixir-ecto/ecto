defmodule Ecto.Pool.TransactionTest do
  use ExUnit.Case, async: true

  alias Ecto.Pool
  alias Ecto.TestPool

  @timeout :infinity

  setup context do
    case = context[:case]
    test = context[:test]
    {:ok, [pool: Module.concat(case, test)]}
  end

  test "worker cleans up the connection when it crashes", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([lazy: false, pool_name: pool])

    conn1 =
      TestPool.transaction(pool, @timeout, fn(:opened, _ref, {_mod, conn1}, queue_time) ->
        assert is_integer(queue_time)
        ref = Process.monitor(conn1)
        Process.exit(conn1, :kill)
        receive do: ({:DOWN, ^ref, _, _, _} -> :ok)
        conn1
      end)

    TestPool.transaction(pool, @timeout, fn(:opened, _ref, {_mod, conn2}, queue_time) ->
      assert is_integer(queue_time)
      assert conn1 != conn2
      refute Process.alive?(conn1)
      assert Process.alive?(conn2)
    end)
  end

  test "transaction can disconnect connection", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([lazy: false, pool_name: pool])

    TestPool.transaction(pool, @timeout,
      fn(:opened, ref, {_mod, conn1}, queue_time) ->
        assert is_integer(queue_time)
        monitor = Process.monitor(conn1)
        assert Pool.break(ref, @timeout) === :ok
        assert TestPool.run(pool, @timeout, fn _, _ -> :ok end) == {:error, :noconnect}
        assert receive do: ({:DOWN, ^monitor, _, _, _} -> :ok)
      end)
  end

  test "disconnects if caller dies during transaction", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([lazy: false, pool_name: pool])

    _ = Process.flag(:trap_exit, true)
    parent = self()
    {:ok, task} = Task.start_link(fn ->
      TestPool.transaction(pool, @timeout, fn(:opened, _ref, {_mod, conn1}, _) ->
        send(parent, {:go, self(), conn1})
        :timer.sleep(:infinity)
      end)
    end)

    assert_receive {:go, ^task, conn1}, @timeout
    Process.exit(task, :kill)
    assert_receive {:EXIT, ^task, :killed}, @timeout

    TestPool.transaction(pool, @timeout, fn(:opened, _ref, {_mod, conn2}, _) ->
      assert conn1 != conn2
      refute Process.alive?(conn1)
      assert Process.alive?(conn2)
    end)
  end

  test "does not disconnect if caller dies after closing", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([lazy: false, pool_name: pool])

    task = Task.async(fn ->
      TestPool.transaction(pool, @timeout, fn(:opened, _ref, {_mod, conn1}, _) ->
        conn1
      end)
    end)

    conn1 = Task.await(task, @timeout)

    TestPool.transaction(pool, @timeout, fn(:opened, _ref, {_mod, conn2}, _) ->
      assert conn1 == conn2
      assert Process.alive?(conn1)
    end)
  end

  test "transactions can be nested", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([lazy: false, pool_name: pool])

    TestPool.transaction(pool, @timeout, fn(:opened, _ref, {_mod, conn1}, queue_time) ->
      assert is_integer(queue_time)
      TestPool.transaction(pool, @timeout, fn(:already_open, _ref, {_mod, conn2}, nil) ->
        assert conn1 == conn2
      end)
    end)
  end

  test "shutdowns connection on break", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([pool_name: pool])

    TestPool.transaction(pool, @timeout, fn(_, ref, {_mod, conn}, _) ->
      mon = Process.monitor(conn)
      TestPool.break(ref, @timeout)
      assert_receive {:DOWN, ^mon, _, _, :shutdown}
    end)
  end

  test "kill connection on break", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([pool_name: pool, shutdown: :brutal_kill])

    TestPool.transaction(pool, @timeout, fn(_, ref, {_mod, conn}, _) ->
      mon = Process.monitor(conn)
      TestPool.break(ref, @timeout)
      assert_receive {:DOWN, ^mon, _, _, :killed}
    end)
  end

  test "shutdown timeout and kill connection on break", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([pool_name: pool, shutdown: 1, trap_exit: true])

    TestPool.transaction(pool, @timeout, fn(_, ref, {_mod, conn}, _) ->
      mon = Process.monitor(conn)
      :erlang.suspend_process(conn)
      TestPool.break(ref, @timeout)
      assert_receive {:DOWN, ^mon, _, _, :killed}
    end)
  end
end
