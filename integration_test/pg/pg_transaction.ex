defmodule Ecto.Integration.PGTransactionTest do
  use ExUnit.Case

  import Ecto.Query
  require Ecto.Integration.PoolRepo, as: PoolRepo

  setup do
    PoolRepo.delete_all "transactions"
    :ok
  end

  defmodule PGTrans do
    use Ecto.Model

    schema "transactions" do
      field :text, :string
    end
  end

  test "nested transaction begin raises and does not rollback to savepoint with same name" do
    PoolRepo.transaction(fn ->
      PoolRepo.transaction(fn ->
        PoolRepo.insert(%PGTrans{text: "pg_1"})
      end)
      try do
        Ecto.Adapters.SQL.query(PoolRepo, "UPDATE transactions SET error = error + 1", [])
      rescue
        _ ->
          :ok
      end
      try do
        PoolRepo.transaction(fn -> flunk "begin did not raise" end)
      rescue
        _ ->
          :ok
      end
    end)
    assert [%PGTrans{text: "pg_1"}] = PoolRepo.all(PGTrans)
  end
end
