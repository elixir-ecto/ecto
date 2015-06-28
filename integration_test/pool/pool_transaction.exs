defmodule Ecto.Integration.PoolTransactionTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.Pool
  alias Ecto.Integration.TestPool

  @timeout :infinity

  test "worker cleans up the connection when it crashes" do
    {:ok, pool} = TestPool.start_link([lazy: false])

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

  test "transaction can disconnect connection" do
    {:ok, pool} = TestPool.start_link([lazy: false])

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

  test "disconnects if fuse raises" do
    {:ok, pool} = TestPool.start_link([lazy: false])

    TestPool.transaction(pool, @timeout, fn(_ref, {_mod, conn}, _, _) ->
      try do
        TestPool.run(pool, @timeout, fn _, _ -> raise "oops" end)
      rescue
        RuntimeError ->
          assert TestPool.run(pool, @timeout, fn _, _ -> :ok end) === {:error, :noconnect}
      end
      refute Process.alive?(conn)
    end)
  end

  test "disconnects if caller dies during transaction" do
    {:ok, pool} = TestPool.start_link([lazy: false])

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

  test "do not disconnect if caller dies after closing" do
    {:ok, pool} = TestPool.start_link([lazy: false])

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
