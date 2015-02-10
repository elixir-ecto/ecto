defmodule Ecto.Integration.DeadlockTest do
  # We can keep this test async as long as it
  # is the only one accessing advisory locks
  use ExUnit.Case, async: true
  require Logger

  alias Ecto.Integration.PoolRepo

  test "deadlocks reset worker" do
    tx1 = self()

    %Task{pid: tx2} = tx2_task = Task.async fn ->
      PoolRepo.transaction fn ->
        acquire_deadlock(tx1, [2, 1])
      end
    end

    tx1_result = PoolRepo.transaction fn ->
      acquire_deadlock(tx2, [1, 2])
    end
    tx2_result = Task.await(tx2_task)

    assert Enum.sort([tx1_result, tx2_result]) == [{:error, :deadlocked}, {:ok, :acquired}]
  end

  defp acquire_deadlock(other_tx, [key1, key2] = _locks) do
    pg_advisory_xact_lock(key1)  # acquire first lock
    Logger.debug "#{inspect self()} acquired #{key1}"
    send other_tx, :acquired1    # signal other_tx that we acquired lock on key1
    assert_receive :acquired1    # wait for other_tx to signal us that it acquired lock on its key1
    Logger.debug "#{inspect self()} continuing"

    try do
      Logger.debug "#{inspect self()} acquiring #{key2}"
      pg_advisory_xact_lock(key2)  # try to acquire lock on key2 (might deadlock)
    rescue
      err in [Postgrex.Error] ->
        Logger.debug "#{inspect self()} got killed by deadlock detection"
        assert %Postgrex.Error{postgres: %{code: "40P01"}} = err

        # At this time Postgres has aborted the transaction, while Ecto still thinks the
        # transaction count is 1.
        {aborted_worker, 1} = Process.get({:ecto_transaction_pid, Process.whereis(PoolRepo.__pool__)})
        %{transactions: 1} = :sys.get_state(aborted_worker)

        try do
          Ecto.Adapters.SQL.query(PoolRepo, "SELECT 1", []);
        rescue
          err in [Postgrex.Error] ->
            # current transaction is aborted, commands ignored until end of transaction block
            assert %Postgrex.Error{postgres: %{code: "25P02"}} = err
        else
          _ -> assert false # tx should be aborted
        end

        # Even aborted transactions can be rolled back.
        PoolRepo.rollback(:deadlocked)
    else
      _ ->
        Logger.debug "#{inspect self()} acquired #{key2}"
        :acquired
    end
  end

  defp pg_advisory_xact_lock(key) do
    %{rows: [{:void}]} =
      Ecto.Adapters.SQL.query(PoolRepo, "SELECT pg_advisory_xact_lock($1);", [key])
  end
end
