defmodule Ecto.Integration.TestTransactionTest do
  use ExUnit.Case

  alias Ecto.Integration.TestRepo

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
          [timeout: 200, pool_timeout: 200]))
    end)
  after
    Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
  end

  test "restart_test_transaction inside another transaction should timeout" do
    TestRepo.transaction(fn ->
      assert {:timeout, _} =
        catch_exit(Ecto.Adapters.SQL.restart_test_transaction(TestRepo,
                   [timeout: 200, pool_timeout: 200]))
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

  defp assert_transaction(mode) do
    {pool, _} = TestRepo.__pool__
    assert Ecto.Adapters.SQL.Sandbox.mode(pool) === mode
  end
end
