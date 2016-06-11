defmodule Ecto.Integration.IsolationTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.PoolRepo
  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  test "aborts on corrupted transactions" do
    PoolRepo.transaction fn ->
      {:error, _} = Ecto.Adapters.SQL.query(PoolRepo, "INVALID", [])
    end

    PoolRepo.transaction fn ->
      # This will taint the whole inner transaction
      {:error, _} = Ecto.Adapters.SQL.query(PoolRepo, "INVALID", [])

      assert_raise Postgrex.Error, ~r/current transaction is aborted/, fn ->
        PoolRepo.insert(%Post{}, skip_transaction: true)
      end
    end
  end

  test "aborts on corrupted transactions even inside sandboxes" do
    TestRepo.transaction fn ->
      {:error, _} = Ecto.Adapters.SQL.query(TestRepo, "INVALID", [])
    end

    TestRepo.transaction fn ->
      # This will taint the whole inner transaction
      {:error, _} = Ecto.Adapters.SQL.query(TestRepo, "INVALID", [])

      assert_raise Postgrex.Error, ~r/current transaction is aborted/, fn ->
        TestRepo.insert(%Post{}, skip_transaction: true)
      end
    end
  end
end
