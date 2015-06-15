defmodule Ecto.Integration.PoolTransactionTest do
  use ExUnit.Case, async: true

  require Ecto.Integration.TestPool, as: Pool
  require Ecto.Integration.Connection, as: Connection
  alias Ecto.Adapters.Pool.Transaction

  @timeout :infinity

  test "worker cleans up the connection when it crashes" do
    {:ok, pool} = Pool.start_link([lazy: false])

    assert {:ok, conn1} =
      Pool.transaction(pool, @timeout, fn(ref, mode, depth, queue_time) ->
        assert mode === :raw
        assert depth === 1
        assert is_integer(queue_time)
        assert {:ok, {_mod, conn1}} = Transaction.connection(ref, @timeout)
        ref = Process.monitor(conn1)
        Process.exit(conn1, :kill)
        receive do: ({:DOWN, ^ref, _, _, _} -> :ok)
        conn1
      end)

    Pool.transaction(pool, @timeout, fn(ref, mode, depth, queue_time) ->
      assert mode === :raw
      assert depth === 1
      assert is_integer(queue_time)
      assert {:ok, {_mod, conn2}} = Transaction.connection(ref, @timeout)
      assert conn1 != conn2
      refute Process.alive?(conn1)
      assert Process.alive?(conn2)
    end)
  end

  test "transaction can disconnect connection" do
    {:ok, pool} = Pool.start_link([lazy: false])

    Pool.transaction(pool, @timeout,
      fn(ref, mode, depth, queue_time) ->
        assert mode === :raw
        assert depth === 1
        assert is_integer(queue_time)
        assert {:ok, {_mod, conn1}} = Transaction.connection(ref, @timeout)
        monitor = Process.monitor(conn1)
        assert Transaction.disconnect(ref, @timeout) === :ok
        assert Transaction.connection(ref, @timeout) == {:error, :noconnect}
        assert receive do: ({:DOWN, ^monitor, _, _, _} -> :ok)
      end)
  end

  test ":raw mode disconnects if fuse raises" do
    {:ok, pool} = Pool.start_link([lazy: false])

    Pool.transaction(pool, @timeout, fn(ref, _, _, _) ->
      assert {:ok, {Connection, conn}} = Transaction.connection(ref, @timeout)
      try do
        Transaction.fuse(ref, @timeout, fn() -> raise "oops" end)
      rescue
        RuntimeError ->
          assert Transaction.connection(ref, @timeout) === {:error, :noconnect}
      end
      refute Process.alive?(conn)
    end)
  end

  test ":raw mode disconnects if caller dies during transaction" do
    {:ok, pool} = Pool.start_link([lazy: false])

    _ = Process.flag(:trap_exit, true)
    parent = self()
    {:ok, task} = Task.start_link(fn ->
      Pool.transaction(pool, @timeout, fn(ref, _, _, _) ->
        {:ok, {_, conn1}} = Transaction.connection(ref, @timeout)
        send(parent, {:go, self(), conn1})
        :timer.sleep(:infinity)
      end)
    end)

    assert_receive {:go, ^task, conn1}, @timeout
    Process.exit(task, :kill)
    assert_receive {:EXIT, ^task, :killed}, @timeout

    Pool.transaction(pool, @timeout, fn(ref, _, _, _) ->
      assert {:ok, {_, conn2}} = Transaction.connection(ref, @timeout)
      assert conn1 != conn2
      refute Process.alive?(conn1)
      assert Process.alive?(conn2)
    end)
  end

  test "do not disconnect if caller dies after closing" do
    {:ok, pool} = Pool.start_link([lazy: false])

    task = Task.async(fn ->
      Pool.transaction(pool, @timeout, fn(ref, _, _, _) ->
        {:ok, {_, conn}} = Transaction.connection(ref, @timeout)
        conn
      end)
    end)

    assert {:ok, conn1} = Task.await(task, @timeout)
    Pool.transaction(pool, @timeout, fn(ref, _, _, _) ->
      assert {:ok, {_, ^conn1}} = Transaction.connection(ref, @timeout)
      assert Process.alive?(conn1)
    end)
  end

  ## Sandbox mode

  test "setting :sandbox does not start a connection" do
    {:ok, pool} = Pool.start_link([lazy: false])

    Pool.transaction(pool, @timeout, fn(ref, mode, _depth, _queue_time) ->
      assert mode === :raw
      assert Transaction.disconnect(ref, @timeout) ===:ok
      assert Transaction.mode(ref, :sandbox, @timeout) === {:error, :noconnect}
    end)
  end


  test "setting :sandbox discovers no connection when connection crashed" do
    {:ok, pool} = Pool.start_link([lazy: false])

    Pool.transaction(pool, @timeout, fn(ref, mode, _depth, _queue_time) ->
      assert mode === :raw
      assert {:ok, {_, conn}} = Transaction.connection(ref, @timeout)
      monitor = Process.monitor(conn)
      Process.exit(conn, :kill)
      receive do: ({:DOWN, ^monitor, _, _, _} -> :ok)
      assert Transaction.mode(ref, :sandbox, @timeout) === {:error, :noconnect}
      assert Transaction.connection(ref, @timeout) === {:error, :noconnect}
    end)
  end

  test "transaction mode is :sandbox when in :sandbox mode" do
    {:ok, pool} = Pool.start_link([lazy: false])

    Pool.transaction(pool, @timeout, fn(ref, mode, _depth, _queue_time) ->
      assert mode === :raw
      assert Transaction.mode(ref, :sandbox, @timeout) === :ok
      Pool.transaction(pool, @timeout, fn(_ref, mode, depth, queue_time) ->
        assert mode === :sandbox
        assert depth === 2
        assert is_nil(queue_time)
      end)
    end)

    Pool.transaction(pool, @timeout, fn(_ref, mode, depth, queue_time) ->
      assert mode === :sandbox
      assert depth === 1
      assert is_integer(queue_time)
   end)
  end

  test "mode returns {:error, :already_mode} when setting mode to active mode" do
    {:ok, pool} = Pool.start_link([lazy: false])

    Pool.transaction(pool, @timeout, fn(ref, mode, _depth, _queue_time) ->
      assert mode === :raw
      assert Transaction.mode(ref, :raw, @timeout) === {:error, :already_mode}
      assert Transaction.mode(ref, :sandbox, @timeout) === :ok
      assert Transaction.mode(ref, :sandbox, @timeout) === {:error, :already_mode}
    end)

    Pool.transaction(pool, @timeout, fn(ref, mode, _depth, _queue_time) ->
      assert mode === :sandbox
      assert Transaction.mode(ref, :sandbox, @timeout) === {:error, :already_mode}
    end)
  end

  test ":sandbox mode does not disconnect if fuse raises after mode change" do
    {:ok, pool} = Pool.start_link([lazy: false])

    Pool.transaction(pool, @timeout, fn(ref, mode, _, _) ->
      assert mode === :raw
      assert Transaction.mode(ref, :sandbox, @timeout) === :ok
      assert {:ok, {Connection, conn}} = Transaction.connection(ref, @timeout)
      try do
        Transaction.fuse(ref, @timeout, fn() -> raise "oops" end)
      rescue
        RuntimeError ->
          assert Transaction.connection(ref, @timeout) === {:error, :noconnect}
      end
      assert Process.alive?(conn)
    end)
  end

  test ":sandbox mode does not disconnect if caller dies after mode change" do
    {:ok, pool} = Pool.start_link([lazy: false])

    _ = Process.flag(:trap_exit, true)
    parent = self()
    {:ok, task} = Task.start_link(fn ->
      Pool.transaction(pool, @timeout, fn(ref, mode, _, _) ->
        assert mode === :raw
        assert Transaction.mode(ref, :sandbox, @timeout) === :ok
        {:ok, {_, conn1}} = Transaction.connection(ref, @timeout)
        send(parent, {:go, self(), conn1})
        :timer.sleep(@timeout)
      end)
    end)

    assert_receive {:go, ^task, conn1}, @timeout
    Process.exit(task, :kill)
    assert_receive {:EXIT, ^task, :killed}, @timeout

    Pool.transaction(pool, @timeout, fn(ref, mode, _, _) ->
      assert mode === :sandbox
      assert {:ok, {_, ^conn1}} = Transaction.connection(ref, @timeout)
      assert Process.alive?(conn1)
    end)
  end

  test ":sandbox mode does not disconnect if fuse raises" do
    {:ok, pool} = Pool.start_link([lazy: false])

    Pool.transaction(pool, @timeout, fn(ref, mode, _, _) ->
      assert mode === :raw
      assert Transaction.mode(ref, :sandbox, @timeout) === :ok
    end)

    Pool.transaction(pool, @timeout, fn(ref, mode, _, _) ->
      assert mode === :sandbox
      assert {:ok, {Connection, conn}} = Transaction.connection(ref, @timeout)
      try do
        Transaction.fuse(ref, @timeout, fn() -> raise "oops" end)
      rescue
        RuntimeError ->
          assert Transaction.connection(ref, @timeout) === {:error, :noconnect}
      end
      assert Process.alive?(conn)
    end)
  end

  test ":sandbox mode does not disconnect if caller dies" do
    {:ok, pool} = Pool.start_link([lazy: false])

    Pool.transaction(pool, @timeout, fn(ref, mode, _, _) ->
      assert mode === :raw
      assert Transaction.mode(ref, :sandbox, @timeout) === :ok
    end)

    _ = Process.flag(:trap_exit, true)
    parent = self()
    {:ok, task} = Task.start_link(fn ->
      Pool.transaction(pool, @timeout, fn(ref, mode, _, _) ->
        assert mode === :sandbox
        assert {:ok, {_, conn1}} = Transaction.connection(ref, @timeout)
        send(parent, {:go, self(), conn1})
        :timer.sleep(@timeout)
      end)
    end)

    assert_receive {:go, ^task, conn1}, @timeout
    Process.exit(task, :kill)
    assert_receive {:EXIT, ^task, :killed}, @timeout

    Pool.transaction(pool, @timeout, fn(ref, mode, _, _) ->
      assert mode === :sandbox
      assert {:ok, {_, ^conn1}} = Transaction.connection(ref, @timeout)
      assert Process.alive?(conn1)
    end)
  end
end
