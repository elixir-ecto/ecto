defmodule Ecto.Integration.TestTransactionTest do
  use ExUnit.Case

  require Ecto.Integration.TestRepo, as: TestRepo

  test "begin, restart and rollback" do
    assert_transaction(1, :raw)
    assert :ok = Ecto.Adapters.SQL.begin_test_transaction(TestRepo)
    assert_transaction(1, :sandbox)
    assert :ok = Ecto.Adapters.SQL.restart_test_transaction(TestRepo)
    assert_transaction(1, :sandbox)
    assert :ok = Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
    assert_transaction(1, :raw)
  after
    Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
  end

  test "restart_test_transaction begins a transaction if one is not running" do
    assert_transaction(1, :raw)
    assert :ok = Ecto.Adapters.SQL.restart_test_transaction(TestRepo)
    assert_transaction(1, :sandbox)
    assert :ok = Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
    assert_transaction(1, :raw)
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

  defp assert_transaction(depth, mode) do
    TestRepo.transaction(fn ->
      {Ecto.Adapters.SQL.Sandbox, pool, _} = TestRepo.__pool__
      assert %{depth: ^depth} =
        Process.get({Ecto.Adapters.Pool, Ecto.Adapters.SQL.Sandbox, pool})
      assert Ecto.Adapters.SQL.Sandbox.mode(pool) === mode
    end)
  end
end
