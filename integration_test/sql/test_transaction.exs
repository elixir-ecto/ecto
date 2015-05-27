defmodule Ecto.Integration.TestTransactionTest do
  use ExUnit.Case

  require Ecto.Integration.TestRepo, as: TestRepo

  test "begin, restart and rollback" do
    assert_transaction_threshold(0)
    assert :ok = Ecto.Adapters.SQL.begin_test_transaction(TestRepo)
    assert_transaction_threshold(1)
    assert :ok = Ecto.Adapters.SQL.restart_test_transaction(TestRepo)
    assert_transaction_threshold(1)
    assert :ok = Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
    assert_transaction_threshold(0)
  after
    Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
  end

  test "restart_test_transaction begins a transaction if one is not running" do
    assert_transaction_threshold(0)
    assert :ok = Ecto.Adapters.SQL.restart_test_transaction(TestRepo)
    assert_transaction_threshold(1)
    assert :ok = Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
    assert_transaction_threshold(0)
  after
    Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
  end

  test "being_test_transaction inside another transaction should fail" do
    TestRepo.transaction(fn ->
      assert_raise RuntimeError, ~r"cannot begin test transaction", fn ->
        Ecto.Adapters.SQL.begin_test_transaction(TestRepo)
      end
    end)
  end

  test "restart_test_transaction inside another transaction should fail" do
    TestRepo.transaction(fn ->
      assert_raise RuntimeError, ~r"cannot restart test transaction", fn ->
        Ecto.Adapters.SQL.restart_test_transaction(TestRepo)
      end
    end)
  end

  test "begin_test_transaction should fail when it has already began" do
    Ecto.Adapters.SQL.begin_test_transaction(TestRepo)
    assert_raise RuntimeError, ~r"cannot begin test transaction", fn ->
      Ecto.Adapters.SQL.begin_test_transaction(TestRepo)
    end
  after
    Ecto.Adapters.SQL.rollback_test_transaction(TestRepo)
  end

  defp assert_transaction_threshold(value) do
    TestRepo.transaction(fn ->
      assert %{threshold: ^value} =
        Process.get({:ecto_transaction_info, elem(TestRepo.__pool__, 0)})
    end)
  end
end
