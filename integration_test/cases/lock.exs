defmodule Ecto.Integration.LockTest do
  # We can keep this test async as long as it
  # is the only one accessing the lock_test table.
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.Integration.PoolRepo

  defmodule LockCounter do
    use Ecto.Model

    schema "lock_counters" do
      field :count, :integer
    end
  end
  # TODO
  # MSSQL Does not allow insertion into identity (serial) columns. 
  #  Removed and assumed that this is the first
  setup do
    lc = %LockCounter{count: 1} |> PoolRepo.insert

    on_exit fn ->
      PoolRepo.delete(lc)
    end

    {:ok, lc: lc}
  end

  test "lock for update", meta do
    query = from(p in LockCounter, where: p.id == ^meta.lc.id, lock: true)
    pid = self

    new_pid =
      spawn_link fn ->
        receive do
          :select_for_update ->
            PoolRepo.transaction(fn ->
              [post] = PoolRepo.all(query)   # this should block until the other trans. commits
              %{post | count: post.count + 1} |> PoolRepo.update
            end)
            send pid, :updated
        after
          5000 -> raise "timeout"
        end
      end

    PoolRepo.transaction(fn ->
      [post] = PoolRepo.all(query)           # select and lock the row
      send new_pid, :select_for_update       # signal second process to begin a transaction
      receive do
        :updated -> raise "missing lock"     # if we get this before committing, our lock failed
      after
        100 -> :ok
      end
      %{post | count: post.count + 1} |> PoolRepo.update
    end)

    receive do
      :updated -> :ok
    after
      5000 -> "timeout"
    end

    # Final count will be 3 if SELECT ... FOR UPDATE worked and 2 otherwise
    assert [%LockCounter{count: 3}] = PoolRepo.all(LockCounter)
  end
end
