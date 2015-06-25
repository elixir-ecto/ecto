defmodule Ecto.Integration.PoolRunTest do
  use ExUnit.Case, async: true

  require Ecto.Integration.TestPool, as: TestPool
  require Ecto.Integration.Connection, as: Connection
  alias Ecto.Adapters.Pool

  @timeout :infinity

  test "worker cleans up the connection when it crashes" do
    {:ok, pool} = TestPool.start_link([lazy: false])

    assert {:ok, conn1} =
      TestPool.run(pool, @timeout, fn(ref, mode, depth, queue_time) ->
        assert mode === :raw
        assert depth === 0
        assert is_integer(queue_time)
        assert {:ok, {_mod, conn1}} = Pool.connection(ref)
        ref = Process.monitor(conn1)
        Process.exit(conn1, :kill)
        receive do: ({:DOWN, ^ref, _, _, _} -> :ok)
        conn1
      end)

    TestPool.run(pool, @timeout, fn(ref, mode, depth, queue_time) ->
      assert mode === :raw
      assert depth === 0
      assert is_integer(queue_time)
      assert {:ok, {_mod, conn2}} = Pool.connection(ref)
      assert conn1 != conn2
      refute Process.alive?(conn1)
      assert Process.alive?(conn2)
    end)
  end

  test "nested run does not increase depth" do
    {:ok, pool} = TestPool.start_link([lazy: false])

    TestPool.transaction(pool, @timeout, fn(_, _, _, _) ->
      TestPool.run(pool, @timeout, fn(_, mode, depth, queue_time) ->
        assert mode === :raw
        assert depth === 1
        assert is_nil(queue_time)
      end)
    end)

    TestPool.run(pool, @timeout, fn(_, _, _, _) ->
      TestPool.run(pool, @timeout, fn(_, mode, depth, queue_time) ->
        assert mode === :raw
        assert depth === 0
        assert is_nil(queue_time)
      end)
    end)
  end

  test "{:error, :notransaction} on transaction inside run" do
    {:ok, pool} = TestPool.start_link([lazy: false])

    TestPool.run(pool, @timeout, fn(_, _, _, _) ->
      assert {:error, :notransaction} =
        TestPool.transaction(pool, @timeout, fn(_, _, _, _) -> end)
    end)
  end

  test "disconnect connection" do
    {:ok, pool} = TestPool.start_link([lazy: false])

    TestPool.run(pool, @timeout,
      fn(ref, mode, depth, queue_time) ->
        assert mode === :raw
        assert depth === 0
        assert is_integer(queue_time)
        assert {:ok, {_mod, conn1}} = Pool.connection(ref)
        monitor = Process.monitor(conn1)
        assert Pool.break(ref, @timeout) === :ok
        assert Pool.connection(ref) == {:error, :noconnect}
        assert receive do: ({:DOWN, ^monitor, _, _, _} -> :ok)
      end)
  end

  test ":raw mode disconnects if fuse raises" do
    {:ok, pool} = TestPool.start_link([lazy: false])

    TestPool.run(pool, @timeout, fn(ref, _, _, _) ->
      assert {:ok, {Connection, conn}} = Pool.connection(ref)
      try do
        Pool.fuse(ref, @timeout, fn() -> raise "oops" end)
      rescue
        RuntimeError ->
          assert Pool.connection(ref) === {:error, :noconnect}
      end
      refute Process.alive?(conn)
    end)
  end

  test ":raw mode does not disconnect if caller dies during run" do
    {:ok, pool} = TestPool.start_link([lazy: false])

    _ = Process.flag(:trap_exit, true)
    parent = self()
    {:ok, task} = Task.start_link(fn ->
      TestPool.run(pool, @timeout, fn(ref, _, _, _) ->
        {:ok, {_, conn}} = Pool.connection(ref)
        send(parent, {:go, self(), conn})
        :timer.sleep(:infinity)
      end)
    end)

    assert_receive {:go, ^task, conn}, @timeout
    Process.exit(task, :kill)
    assert_receive {:EXIT, ^task, :killed}, @timeout

    TestPool.run(pool, @timeout, fn(ref, _, _, _) ->
      assert {:ok, {_, ^conn}} = Pool.connection(ref)
      assert Process.alive?(conn)
    end)
  end

  ## Sandbox mode

  test "setting :sandbox does not start a connection" do
    {:ok, pool} = TestPool.start_link([lazy: false])

    TestPool.run(pool, @timeout, fn(ref, mode, _depth, _queue_time) ->
      assert mode === :raw
      assert Pool.break(ref, @timeout) ===:ok
      assert Pool.mode(ref, :sandbox, @timeout) === {:error, :noconnect}
    end)
  end

  test ":sandbox mode does not disconnect if fuse raises" do
    {:ok, pool} = TestPool.start_link([lazy: false])

    TestPool.transaction(pool, @timeout, fn(ref, mode, _, _) ->
      assert mode === :raw
      assert Pool.mode(ref, :sandbox, @timeout) === :ok
    end)

    TestPool.run(pool, @timeout, fn(ref, mode, _, _) ->
      assert mode === :sandbox
      assert {:ok, {Connection, conn}} = Pool.connection(ref)
      try do
        Pool.fuse(ref, @timeout, fn() -> raise "oops" end)
      rescue
        RuntimeError ->
          assert Pool.connection(ref) === {:error, :noconnect}
      end
      assert Process.alive?(conn)
    end)
  end

  test ":sandbox mode does not disconnect if caller dies" do
    {:ok, pool} = TestPool.start_link([lazy: false])

    TestPool.transaction(pool, @timeout, fn(ref, mode, _, _) ->
      assert mode === :raw
      assert Pool.mode(ref, :sandbox, @timeout) === :ok
    end)

    _ = Process.flag(:trap_exit, true)
    parent = self()
    {:ok, task} = Task.start_link(fn ->
      TestPool.run(pool, @timeout, fn(ref, mode, _, _) ->
        assert mode === :sandbox
        assert {:ok, {_, conn1}} = Pool.connection(ref)
        send(parent, {:go, self(), conn1})
        :timer.sleep(@timeout)
      end)
    end)

    assert_receive {:go, ^task, conn1}, @timeout
    Process.exit(task, :kill)
    assert_receive {:EXIT, ^task, :killed}, @timeout

    TestPool.run(pool, @timeout, fn(ref, mode, _, _) ->
      assert mode === :sandbox
      assert {:ok, {_, ^conn1}} = Pool.connection(ref)
      assert Process.alive?(conn1)
    end)
  end
end
