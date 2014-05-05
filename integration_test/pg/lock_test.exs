defmodule Ecto.Integration.LockTest do
  use Ecto.Integration.Postgres.Case

  import Ecto.Query
  alias Ecto.Adapters.Postgres

  defmodule TestRepo1 do
    use Ecto.Repo, adapter: Postgres

    def conf do
      parse_url "ecto://postgres:postgres@localhost/ecto_test?size=10"
    end
  end

  defmodule LockCounter do
    use Ecto.Model

    schema "lock_counters" do
      field :count, :integer
    end
  end

  setup_all do
    { :ok, _ } = TestRepo1.start_link
    :ok
  end

  teardown_all do
    :ok = TestRepo1.stop
  end

  setup do
    %LockCounter{id: 42, count: 1} |> TestRepo1.insert
    :ok
  end

  teardown do
    TestRepo1.get(LockCounter, 42) |> TestRepo1.delete
    :ok
  end

  test "lock for update" do
    query = from(p in LockCounter, where: p.id == 42, lock: true)
    pid = self

    new_pid =
      spawn_link fn ->
        receive do
          :select_for_update ->
            TestRepo1.transaction(fn ->
              [post] = TestRepo1.all(query)   # this should block until the other trans. commits
              %{post | count: post.count + 1} |> TestRepo1.update
              send pid, :updated
            end)
        after
          5000 -> raise "timeout"
        end
      end

    TestRepo1.transaction(fn ->
      [post] = TestRepo1.all(query)           # select and lock the row
      send new_pid, :select_for_update        # signal second process to begin a transaction
      receive do
        :updated -> raise "missing lock"      # if we get this before committing, our lock failed
      after
        100 -> :ok
      end
      %{post | count: post.count + 1} |> TestRepo1.update
    end)

    receive do
      :updated -> :ok
    after
      5000 -> "timeout"
    end

    # final count will be 3 if SELECT ... FOR UPDATE worked and 2 otherwise
    assert [%LockCounter{count: 3}] = TestRepo1.all(LockCounter)
  end
end
