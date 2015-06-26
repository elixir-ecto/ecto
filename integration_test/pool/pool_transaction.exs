defmodule Ecto.Integration.PoolTransactionTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.Pool
  alias Ecto.Integration.TestPool

  @timeout :infinity

  setup context do
    case = context[:case]
    test = context[:test]
    {:ok, [pool: Module.concat(case, test)]}
  end

  test "worker cleans up the connection when it crashes", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([lazy: false, name: pool])

    assert {:ok, conn1} =
      TestPool.transaction(pool, @timeout, fn(_ref, {_mod, conn1}, depth, queue_time) ->
        assert depth === 1
        assert is_integer(queue_time)
        ref = Process.monitor(conn1)
        Process.exit(conn1, :kill)
        receive do: ({:DOWN, ^ref, _, _, _} -> :ok)
        conn1
      end)

    TestPool.transaction(pool, @timeout, fn(_ref, {_mod, conn2}, depth, queue_time) ->
      assert depth === 1
      assert is_integer(queue_time)
      assert conn1 != conn2
      refute Process.alive?(conn1)
      assert Process.alive?(conn2)
    end)
  end

  test "transaction can disconnect connection", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([lazy: false, name: pool])

    TestPool.transaction(pool, @timeout,
      fn(ref, {_mod, conn1}, depth, queue_time) ->
        assert depth === 1
        assert is_integer(queue_time)
        monitor = Process.monitor(conn1)
        assert Pool.break(ref, @timeout) === :ok
        assert TestPool.run(pool, @timeout, fn _, _ -> :ok end) == {:error, :noconnect}
        assert receive do: ({:DOWN, ^monitor, _, _, _} -> :ok)
      end)
  end

  test "disconnects if fuse raises", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([lazy: false, name: pool])

    TestPool.transaction(pool, @timeout, fn(_ref, {_mod, conn}, _, _) ->
      monitor = Process.monitor(conn)
      try do
        TestPool.run(pool, @timeout, fn _, _ -> raise "oops" end)
      rescue
        RuntimeError ->
          assert TestPool.run(pool, @timeout, fn _, _ -> :ok end) === {:error, :noconnect}
      end
      assert_receive {:DOWN, ^monitor, _, _, _}
    end)
  end

  test "disconnects if caller dies during transaction", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([lazy: false, name: pool])

    _ = Process.flag(:trap_exit, true)
    parent = self()
    {:ok, task} = Task.start_link(fn ->
      TestPool.transaction(pool, @timeout, fn(_ref, {_mod, conn1}, _, _) ->
        send(parent, {:go, self(), conn1})
        :timer.sleep(:infinity)
      end)
    end)

    assert_receive {:go, ^task, conn1}, @timeout
    Process.exit(task, :kill)
    assert_receive {:EXIT, ^task, :killed}, @timeout

    TestPool.transaction(pool, @timeout, fn(_ref, {_mod, conn2}, _, _) ->
      assert conn1 != conn2
      refute Process.alive?(conn1)
      assert Process.alive?(conn2)
    end)
  end

  test "do not disconnect if caller dies after closing", context do
    pool = context[:pool]
    {:ok, _} = TestPool.start_link([lazy: false, name: pool])

    task = Task.async(fn ->
      TestPool.transaction(pool, @timeout, fn(_ref, {_mod, conn1}, _, _) ->
        conn1
      end)
    end)

    assert {:ok, conn1} = Task.await(task, @timeout)
    TestPool.transaction(pool, @timeout, fn(_ref, {_mod, conn2}, _, _) ->
      assert conn1 == conn2
      assert Process.alive?(conn1)
    end)
  end
end
