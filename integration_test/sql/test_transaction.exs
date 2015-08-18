defmodule Ecto.Integration.TestTransactionTest do
  use ExUnit.Case

  alias Ecto.Integration.TestRepo
  alias Ecto.Pool

  @ref {Ecto.Pool, Ecto.Adapters.SQL.Sandbox, elem(TestRepo.__pool__, 1)}
  @timeout :infinity

  test "sandbox pool is lazy" do
    assert {:ok, _} = Ecto.Adapters.SQL.Sandbox.start_link(UnknownModuleBecauseLazy, [])
  end

  test "begin, restart and rollback" do
    assert_transaction(:raw)
    assert :ok = Ecto.Adapters.SQL.begin_test_transaction(TestRepo)
    assert_transaction(:sandbox)
    assert :ok = Ecto.Adapters.SQL.restart_test_transaction(TestRepo)
    assert_transaction(:sandbox)
    assert :ok = Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
    assert_transaction(:raw)
  after
    Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
  end

  test "restart_test_transaction begins a transaction if one is not running" do
    assert_transaction(:raw)
    assert :ok = Ecto.Adapters.SQL.restart_test_transaction(TestRepo)
    assert_transaction(:sandbox)
    assert :ok = Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
    assert_transaction(:raw)
  after
    Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
  end

  test "begin_test_transaction inside another transaction should timeout" do
    TestRepo.transaction(fn ->
      assert {:timeout, _} =
        catch_exit(Ecto.Adapters.SQL.restart_test_transaction(TestRepo,
          [timeout: 200]))
    end)
  after
    Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
  end

  test "restart_test_transaction inside another transaction should timeout" do
    TestRepo.transaction(fn ->
      assert {:timeout, _} =
        catch_exit(Ecto.Adapters.SQL.restart_test_transaction(TestRepo,
                   [timeout: 200]))
    end)
  after
    Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
  end

  test "begin_test_transaction should fail when it has already began" do
    Ecto.Adapters.SQL.begin_test_transaction(TestRepo)
    assert_raise RuntimeError, ~r"cannot begin test transaction", fn ->
      Ecto.Adapters.SQL.begin_test_transaction(TestRepo)
    end
  after
    Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
  end

  test "sandbox mode does not disconnect on transaction break" do
    Ecto.Adapters.SQL.begin_test_transaction(TestRepo)
    {:ok, conn} = TestRepo.transaction(fn() ->
        assert %{conn: conn} = Process.get(@ref)
        Pool.break(@ref, @timeout)
        conn
      end)

    TestRepo.transaction(fn() ->
      assert %{conn: ^conn} = Process.get(@ref)
      {_, pid} = conn
      assert Process.alive?(pid)
    end)
  after
    Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
  end

  test "sandbox mode does not disconnect on run break" do
    Ecto.Adapters.SQL.begin_test_transaction(TestRepo)
    {_, pool_mod, pool} = @ref
    try do
      Pool.run(pool_mod, pool, @timeout, fn(conn, _) ->
        throw(conn)
      end)
    catch
      :throw, conn ->
        TestRepo.transaction(fn() ->
          assert %{conn: ^conn} = Process.get(@ref)
        end)
    end
  after
    Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
  end

  test "sandbox mode does not disconnect if transaction caller dies" do
    Ecto.Adapters.SQL.begin_test_transaction(TestRepo)
    _ = Process.flag(:trap_exit, true)

    parent = self()
    {:ok, task} = Task.start_link(fn ->
      TestRepo.transaction(fn() ->
        assert %{conn: conn} = Process.get(@ref)
        send(parent, {:go, self(), conn})
        :timer.sleep(@timeout)
      end)
    end)

    assert_receive {:go, ^task, conn}, @timeout
    Process.exit(task, :shutdown)
    assert_receive {:EXIT, ^task, :shutdown}, @timeout

    TestRepo.transaction(fn() ->
      %{conn: ^conn} = Process.get(@ref)
      {_, pid} = conn
      assert Process.alive?(pid)
    end)
  after
    Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
  end

  test "sandbox mode does not disconnect if run caller dies" do
    Ecto.Adapters.SQL.begin_test_transaction(TestRepo)
    _ = Process.flag(:trap_exit, true)

    parent = self()
    {:ok, task} = Task.start_link(fn ->
      {_, pool_mod, pool} = @ref
      Pool.run(pool_mod, pool, @timeout, fn(conn, _) ->
        send(parent, {:go, self(), conn})
        :timer.sleep(@timeout)
      end)
    end)

    assert_receive {:go, ^task, conn}, @timeout
    Process.exit(task, :shutdown)
    assert_receive {:EXIT, ^task, :shutdown}, @timeout

    TestRepo.transaction(fn() ->
      assert %{conn: ^conn} = Process.get(@ref)
      {_, pid} = conn
      assert Process.alive?(pid)
    end)
  after
    Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
  end

  test "raw mode disconnects on transaction break" do
    conn = TestRepo.transaction(fn() ->
      assert %{conn: conn} = Process.get(@ref)
      Pool.break(@ref, @timeout)
      conn
    end)

    TestRepo.transaction(fn() ->
      %{conn: other} = Process.get(@ref)
      assert conn != other
    end)
  end

  test "raw mode disconnects if transaction caller dies" do
    _ = Process.flag(:trap_exit, true)
    parent = self()
    {:ok, task} = Task.start_link(fn ->
      TestRepo.transaction(fn() ->
        assert %{conn: conn1} = Process.get(@ref)
        send(parent, {:go, self(), conn1})
        :timer.sleep(@timeout)
      end)
    end)

    assert_receive {:go, ^task, conn1}, @timeout
    Process.exit(task, :shutdown)
    assert_receive {:EXIT, ^task, :shutdown}, @timeout

    TestRepo.transaction(fn() ->
      %{conn: conn2} = Process.get(@ref)
      assert conn1 !== conn2
      {_, pid1} = conn1
      refute Process.alive?(pid1)
      {_, pid2} = conn2
      assert Process.alive?(pid2)
    end)
  end

  test "raw mode does not disconnects if run caller dies" do
    _ = Process.flag(:trap_exit, true)

    parent = self()
    {:ok, task} = Task.start_link(fn ->
      {_, pool_mod, pool} = @ref
      Pool.run(pool_mod, pool, @timeout, fn(conn, _) ->
        send(parent, {:go, self(), conn})
        :timer.sleep(@timeout)
      end)
    end)

    assert_receive {:go, ^task, conn}, @timeout
    Process.exit(task, :shutdown)
    assert_receive {:EXIT, ^task, :shutdown}, @timeout

    TestRepo.transaction(fn() ->
      assert %{conn: ^conn} = Process.get(@ref)
      {_, pid} = conn
      assert Process.alive?(pid)
    end)
  end

  defp assert_transaction(mode) do
    TestRepo.transaction(fn ->
      {_, pool, _} = TestRepo.__pool__
      assert Ecto.Adapters.SQL.Sandbox.mode(pool) === mode
    end)
  end
end
