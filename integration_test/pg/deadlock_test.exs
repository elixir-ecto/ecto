defmodule Ecto.Integration.DeadlockTest do
  # We can keep this test async as long as it
  # is the only one accessing advisory locks
  use ExUnit.Case, async: true
  require Logger

  @timeout 500
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
    send other_tx, :acquired1            # signal other_tx that we acquired lock on key1
    assert_receive :acquired1, @timeout  # wait for other_tx to signal us that it acquired lock on its key1
    Logger.debug "#{inspect self()} continuing"

    try do
      Logger.debug "#{inspect self()} acquiring #{key2}"
      pg_advisory_xact_lock(key2)  # try to acquire lock on key2 (might deadlock)
    rescue
      err in [Postgrex.Error] ->
        Logger.debug "#{inspect self()} got killed by deadlock detection"
        assert %Postgrex.Error{postgres: %{code: :deadlock_detected}} = err

        assert_tx_aborted

        # Trapping a transaction should still be fine.
        try do
          Process.flag(:trap_exit, true)
          PoolRepo.transaction fn -> :ok end
        catch
          class, msg ->
            Logger.debug inspect([class, msg])
        after
          Process.flag(:trap_exit, false)
        end

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
      Ecto.Adapters.SQL.query!(PoolRepo, "SELECT 1", []);
    rescue
      err in [Postgrex.Error] ->
        # current transaction is aborted, commands ignored until end of transaction block
        assert %Postgrex.Error{postgres: %{code: :in_failed_sql_transaction}} = err
    else
      _ -> flunk "transaction should be aborted"
    end
  end

  defp pg_advisory_xact_lock(key) do
    %{rows: [[:void]]} =
      Ecto.Adapters.SQL.query!(PoolRepo, "SELECT pg_advisory_xact_lock($1);", [key])
  end
end
