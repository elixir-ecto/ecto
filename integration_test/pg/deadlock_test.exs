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

  test "parent tx keeps locks when nested tx aborts" do
    parent = self()

    %Task{pid: other_tx} = other_tx_task = Task.async fn ->
      PoolRepo.transaction fn ->
        pg_advisory_xact_lock(1)
        send(parent, :acquired1)
        assert_receive :continue

        {:error, :continue} = PoolRepo.transaction fn ->
          try do
            pg_advisory_xact_lock(2)
            send(parent, :acquired2)
            assert_receive :continue
            Ecto.Adapters.SQL.query(PoolRepo, "INVALID SQL --> ABORTS TRANSACTION", [])
          rescue
            err in [Postgrex.Error] ->
              # syntax error
              assert %Postgrex.Error{postgres: %{code: "42601"}} = err
              assert_tx_aborted
              PoolRepo.rollback(:continue)
          else
            _ -> assert false # should catch syntax error
          end
        end

        send(parent, :rollbacked_to_savepoint)
        assert_receive :continue
      end
    end

    PoolRepo.transaction fn ->
      assert_receive :acquired1 # other_tx has acquired lock on 1
      refute pg_try_advisory_xact_lock(1) # we can't get lock on 1
      send(other_tx, :continue)

      assert_receive :acquired2 # other_tx has acquired lock on 2 in a nested tx
      refute pg_try_advisory_xact_lock(1) # we still can't get lock on 1
      refute pg_try_advisory_xact_lock(2) # we now can't get lock on 2
      send(other_tx, :continue)

      assert_receive :rollbacked_to_savepoint # other tx has rolled back nested tx after it aborted
      refute pg_try_advisory_xact_lock(1) # we still can't get lock on 1
      assert pg_try_advisory_xact_lock(2) # but we can get lock on 2
      send(other_tx, :continue)

      Task.await(other_tx_task)
      assert pg_try_advisory_xact_lock(1) # after other_tx is commited we can get a lock on 1
    end
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

        # At this time the transaction count is actually 0 not 1 because Postgres
        # has killed the tx but Ecto doesn't know/care.
        {aborted_worker, _} = Process.get({:ecto_transaction_pid, Process.whereis(PoolRepo.__pool__)})
        %{transactions: 1} = :sys.get_state(aborted_worker)

        assert_tx_aborted

        # Even aborted transactions can be rolled back.
        PoolRepo.rollback(:deadlocked)
    else
      _ ->
        Logger.debug "#{inspect self()} acquired #{key2}"
        :acquired
    end
  end

  defp assert_tx_aborted do
    try do
      Ecto.Adapters.SQL.query(PoolRepo, "SELECT 1", []);
    rescue
      err in [Postgrex.Error] ->
        # current transaction is aborted, commands ignored until end of transaction block
        assert %Postgrex.Error{postgres: %{code: "25P02"}} = err
    else
      _ -> assert false # tx should be aborted
    end
  end

  defp pg_advisory_xact_lock(key) do
    %{rows: [{:void}]} =
      Ecto.Adapters.SQL.query(PoolRepo, "SELECT pg_advisory_xact_lock($1);", [key])
  end

  defp pg_try_advisory_xact_lock(key) do
    %{rows: [{result}]} =
      Ecto.Adapters.SQL.query(PoolRepo, "SELECT pg_try_advisory_xact_lock($1);", [key])
    result
  end

end
