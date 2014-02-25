defmodule Ecto.Integration.LockTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  alias Ecto.Adapters.Postgres

  defmodule TestRepo1 do
    use Ecto.Repo, adapter: Postgres

    def url do
      "ecto://postgres:postgres@localhost/ecto_test?size=10"
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
    Postgres.query(TestRepo1, "INSERT INTO locks VALUES (42, 1)")
    :ok
  end

  defmodule Lock do
    use Ecto.Model

    queryable "locks" do
      field :value, :integer
    end
  end

  test "lock for update" do
    query = from(t in Lock, where: t.id == 42, lock: true)
    pid = self
    
    new_pid =
      spawn_link fn ->
        receive do
          :select_for_update ->
            TestRepo1.transaction(fn ->
              [lock] = TestRepo1.all(query)
              lock.value(lock.value + 1) |> TestRepo1.update
              send pid, :updated
            end)
        after
          5000 -> raise "timeout"
        end
      end
    
    TestRepo1.transaction(fn ->
      [lock] = TestRepo1.all(query)
      send new_pid, :select_for_update
      receive do
        :updated -> raise "missing lock"
      after
        100 -> :ok
      end
      lock.value(lock.value + 1) |> TestRepo1.update
    end)

    assert [Lock.Entity[value: 3]] = TestRepo1.all(Lock)
  end
 
end