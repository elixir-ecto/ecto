defmodule Ecto.Adapters.PoolboyTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.Poolboy

  defmodule Pool do
    alias Ecto.Adapters.PoolboyTest.Connection
    def start_link(opts), do: Poolboy.start_link(Connection, [size: 1] ++ opts)
  end

  defmodule Connection do
    def connect(_opts) do
      Agent.start_link(fn -> [] end)
    end

    def disconnect(conn) do
      Agent.stop(conn)
    end
  end

  @timeout :infinity

  test "worker starts without an active connection but connects on transaction" do
    {:ok, pool} = Pool.start_link([])
    worker = :poolboy.checkout(pool, false)
    assert Process.alive?(worker)
    refute :sys.get_state(worker).conn
    :poolboy.checkin(pool, worker)

    Poolboy.transaction(pool, @timeout, fn(ref, mode, depth, queue_time) ->
      assert {:ok, {Connection, conn}} = Poolboy.connection(ref)
      assert Process.alive?(conn)
      assert mode === :raw
      assert depth === 0
      assert is_integer(queue_time)
    end)
  end

  test "worker starts with an active connection" do
    {:ok, pool} = Pool.start_link([lazy: false])
    worker = :poolboy.checkout(pool, false)
    assert Process.alive?(worker)
    assert :sys.get_state(worker).conn
  end

  test "worker cleans up the connection when it crashes" do
    {:ok, pool} = Pool.start_link([lazy: false])

    assert {:ok, conn1} =
      Poolboy.transaction(pool, @timeout, fn(ref, mode, depth, queue_time) ->
        assert mode === :raw
        assert depth === 0
        assert is_integer(queue_time)
        assert {:ok, {_mod, conn1}} = Poolboy.connection(ref)
        ref = Process.monitor(conn1)
        Process.exit(conn1, :kill)
        receive do: ({:DOWN, ^ref, _, _, _} -> :ok)
        conn1
      end)

    Poolboy.transaction(pool, @timeout, fn(ref, mode, depth, queue_time) ->
      assert mode === :raw
      assert depth === 0
      assert is_integer(queue_time)
      assert {:ok, {_mod, conn2}} = Poolboy.connection(ref)
      assert conn1 != conn2
      refute Process.alive?(conn1)
      assert Process.alive?(conn2)
    end)
  end

  test "transaction can disconnect connection" do
    {:ok, pool} = Pool.start_link([lazy: false])

    Poolboy.transaction(pool, @timeout,
      fn(ref, mode, depth, queue_time) ->
        assert mode === :raw
        assert depth === 0
        assert is_integer(queue_time)
        assert {:ok, {_mod, conn1}} = Poolboy.connection(ref)
        monitor = Process.monitor(conn1)
        assert Poolboy.disconnect(ref, @timeout) === :ok
        assert Poolboy.connection(ref) == {:error, :noconnect}
        assert receive do: ({:DOWN, ^monitor, _, _, _} -> :ok)
      end)
  end

  test ":raw mode disconnects if caller dies during transaction" do
    {:ok, pool} = Pool.start_link([lazy: false])

    _ = Process.flag(:trap_exit, true)
    parent = self()
    {:ok, task} = Task.start_link(fn ->
      Poolboy.transaction(pool, @timeout, fn(ref, _, _, _) ->
        {:ok, {_, conn1}} = Poolboy.connection(ref)
        send(parent, {:go, self(), conn1})
        :timer.sleep(:infinity)
      end)
    end)

    assert_receive {:go, ^task, conn1}, @timeout
    Process.exit(task, :kill)
    assert_receive {:EXIT, ^task, :killed}, @timeout

    Poolboy.transaction(pool, @timeout, fn(ref, _, _, _) ->
      assert {:ok, {_, conn2}} = Poolboy.connection(ref)
      assert conn1 != conn2
      refute Process.alive?(conn1)
      assert Process.alive?(conn2)
    end)
  end

  test "do not disconnect if caller dies after closing" do
    {:ok, pool} = Pool.start_link([lazy: false])

    task = Task.async(fn ->
      Poolboy.transaction(pool, @timeout, fn(ref, _, _, _) ->
        {:ok, {_, conn}} = Poolboy.connection(ref)
        conn
      end)
    end)

    assert {:ok, conn1} = Task.await(task, @timeout)
    Poolboy.transaction(pool, @timeout, fn(ref, _, _, _) ->
      assert {:ok, {_, ^conn1}} = Poolboy.connection(ref)
      assert Process.alive?(conn1)
    end)
  end

  ## Sandbox mode

  test "setting :sandbox does not start a connection" do
    {:ok, pool} = Pool.start_link([lazy: false])

    Poolboy.transaction(pool, @timeout, fn(ref, mode, _depth, _queue_time) ->
      assert mode === :raw
      assert Poolboy.disconnect(ref, @timeout) ===:ok
      assert Poolboy.mode(ref, :sandbox, @timeout) === {:error, :noconnect}
    end)
  end


  test "setting :sandbox discovers no connection when connection crashed" do
    {:ok, pool} = Pool.start_link([lazy: false])

    Poolboy.transaction(pool, @timeout, fn(ref, mode, _depth, _queue_time) ->
      assert mode === :raw
      assert {:ok, {_, conn}} = Poolboy.connection(ref)
      monitor = Process.monitor(conn)
      Process.exit(conn, :kill)
      receive do: ({:DOWN, ^monitor, _, _, _} -> :ok)
      assert Poolboy.mode(ref, :sandbox, @timeout) === {:error, :noconnect}
      assert Poolboy.connection(ref) === {:error, :noconnect}
    end)
  end

  test "transaction mode is :sandbox when in :sandbox mode" do
    {:ok, pool} = Pool.start_link([lazy: false])

    Poolboy.transaction(pool, @timeout, fn(ref, mode, _depth, _queue_time) ->
      assert mode === :raw
      assert Poolboy.mode(ref, :sandbox, @timeout) === :ok
      Poolboy.transaction(pool, @timeout, fn(_ref, mode, depth, queue_time) ->
        assert mode === :sandbox
        assert depth === 1
        assert is_nil(queue_time)
      end)
    end)

    Poolboy.transaction(pool, @timeout, fn(_ref, mode, depth, queue_time) ->
      assert mode === :sandbox
      assert depth === 0
      assert is_integer(queue_time)
   end)
  end

  test "mode returns {:error, :already_mode} when setting mode to active mode" do
    {:ok, pool} = Pool.start_link([lazy: false])

    Poolboy.transaction(pool, @timeout, fn(ref, mode, _depth, _queue_time) ->
      assert mode === :raw
      assert Poolboy.mode(ref, :raw, @timeout) === {:error, :already_mode}
      assert Poolboy.mode(ref, :sandbox, @timeout) === :ok
      assert Poolboy.mode(ref, :sandbox, @timeout) === {:error, :already_mode}
    end)

    Poolboy.transaction(pool, @timeout, fn(ref, mode, _depth, _queue_time) ->
      assert mode === :sandbox
      assert Poolboy.mode(ref, :sandbox, @timeout) === {:error, :already_mode}
    end)
  end

  test ":sandbox mode does not disconnect if caller dies after mode change" do
    {:ok, pool} = Pool.start_link([lazy: false])

    _ = Process.flag(:trap_exit, true)
    parent = self()
    {:ok, task} = Task.start_link(fn ->
      Poolboy.transaction(pool, @timeout, fn(ref, mode, _, _) ->
        assert mode === :raw
        assert Poolboy.mode(ref, :sandbox, @timeout) === :ok
        {:ok, {_, conn1}} = Poolboy.connection(ref)
        send(parent, {:go, self(), conn1})
        :timer.sleep(@timeout)
      end)
    end)

    assert_receive {:go, ^task, conn1}, @timeout
    Process.exit(task, :kill)
    assert_receive {:EXIT, ^task, :killed}, @timeout

    Poolboy.transaction(pool, @timeout, fn(ref, mode, _, _) ->
      assert mode === :sandbox
      assert {:ok, {_, ^conn1}} = Poolboy.connection(ref)
      assert Process.alive?(conn1)
    end)
  end

  test ":sandbox mode does not disconnect if caller dies" do
    {:ok, pool} = Pool.start_link([lazy: false])

    Poolboy.transaction(pool, @timeout, fn(ref, mode, _, _) ->
      assert mode === :raw
      assert Poolboy.mode(ref, :sandbox, @timeout) === :ok
    end)

    _ = Process.flag(:trap_exit, true)
    parent = self()
    {:ok, task} = Task.start_link(fn ->
      Poolboy.transaction(pool, @timeout, fn(ref, mode, _, _) ->
        assert mode === :sandbox
        assert {:ok, {_, conn1}} = Poolboy.connection(ref)
        send(parent, {:go, self(), conn1})
        :timer.sleep(@timeout)
      end)
    end)

    assert_receive {:go, ^task, conn1}, @timeout
    Process.exit(task, :kill)
    assert_receive {:EXIT, ^task, :killed}, @timeout

    Poolboy.transaction(pool, @timeout, fn(ref, mode, _, _) ->
      assert mode === :sandbox
      assert {:ok, {_, ^conn1}} = Poolboy.connection(ref)
      assert Process.alive?(conn1)
    end)
  end
end
