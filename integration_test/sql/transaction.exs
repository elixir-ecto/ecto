defmodule Ecto.Integration.TransactionTest do
  # We can keep this test async as long as it
  # is the only one access the transactions table
  use Ecto.Integration.Case, async: true

  import Ecto.Query
  alias Ecto.Integration.PoolRepo # Used for writes
  alias Ecto.Integration.TestRepo # Used for reads

  @moduletag :capture_log

  defmodule UniqueError do
    defexception message: "unique error"
  end

  setup do
    PoolRepo.delete_all "transactions"
    :ok
  end

  defmodule Trans do
    use Ecto.Schema

    schema "transactions" do
      field :text, :string
    end
  end

  test "transaction returns value" do
    refute PoolRepo.in_transaction?
    {:ok, val} = PoolRepo.transaction(fn ->
      assert PoolRepo.in_transaction?
      {:ok, val} =
        PoolRepo.transaction(fn ->
          assert PoolRepo.in_transaction?
          42
        end)
      assert PoolRepo.in_transaction?
      val
    end)
    refute PoolRepo.in_transaction?
    assert val == 42
  end

  test "transaction re-raises" do
    assert_raise UniqueError, fn ->
      PoolRepo.transaction(fn ->
        PoolRepo.transaction(fn ->
          raise UniqueError
        end)
      end)
    end
  end

  test "transaction commits" do
    PoolRepo.transaction(fn ->
      e = PoolRepo.insert!(%Trans{text: "1"})
      assert [^e] = PoolRepo.all(Trans)
      assert [] = TestRepo.all(Trans)
    end)

    assert [%Trans{text: "1"}] = PoolRepo.all(Trans)
  end

  test "transaction rolls back" do
    try do
      PoolRepo.transaction(fn ->
        e = PoolRepo.insert!(%Trans{text: "2"})
        assert [^e] = PoolRepo.all(Trans)
        assert [] = TestRepo.all(Trans)
        raise UniqueError
      end)
    rescue
      UniqueError -> :ok
    end

    assert [] = TestRepo.all(Trans)
  end

  test "transaction rolls back per repository" do
    message = "cannot call rollback outside of transaction"

    assert_raise RuntimeError, message, fn ->
      PoolRepo.rollback(:done)
    end

    assert_raise RuntimeError, message, fn ->
      TestRepo.transaction fn ->
        PoolRepo.rollback(:done)
      end
    end
  end

  test "nested transaction partial rollback" do
    assert PoolRepo.transaction(fn ->
      e1 = PoolRepo.insert!(%Trans{text: "3"})
      assert [^e1] = PoolRepo.all(Trans)

      try do
        PoolRepo.transaction(fn ->
          e2 = PoolRepo.insert!(%Trans{text: "4"})
          assert [^e1, ^e2] = PoolRepo.all(from(t in Trans, order_by: t.text))
          raise UniqueError
        end)
      rescue
        UniqueError -> :ok
      end

      assert_raise DBConnection.ConnectionError, "transaction rolling back",
        fn() -> PoolRepo.insert!(%Trans{text: "5"}) end
    end) == {:error, :rollback}

    assert TestRepo.all(Trans) == []
  end

  test "manual rollback doesn't bubble up" do
    x = PoolRepo.transaction(fn ->
      e = PoolRepo.insert!(%Trans{text: "6"})
      assert [^e] = PoolRepo.all(Trans)
      PoolRepo.rollback(:oops)
    end)

    assert x == {:error, :oops}
    assert [] = TestRepo.all(Trans)
  end

  test "manual rollback bubbles up on nested transaction" do
    assert PoolRepo.transaction(fn ->
      e = PoolRepo.insert!(%Trans{text: "6"})
      assert [^e] = PoolRepo.all(Trans)
      assert {:error, :oops} = PoolRepo.transaction(fn ->
        PoolRepo.rollback(:oops)
      end)
      assert_raise DBConnection.ConnectionError, "transaction rolling back",
        fn() -> PoolRepo.insert!(%Trans{text: "5"}) end
    end) == {:error, :rollback}

    assert [] = TestRepo.all(Trans)
  end

  test "transactions are not shared in repo" do
    pid = self()

    new_pid = spawn_link fn ->
      PoolRepo.transaction(fn ->
        e = PoolRepo.insert!(%Trans{text: "7"})
        assert [^e] = PoolRepo.all(Trans)
        send(pid, :in_transaction)
        receive do
          :commit -> :ok
        after
          5000 -> raise "timeout"
        end
      end)
      send(pid, :committed)
    end

    receive do
      :in_transaction -> :ok
    after
      5000 -> raise "timeout"
    end
    assert [] = PoolRepo.all(Trans)

    send(new_pid, :commit)
    receive do
      :committed -> :ok
    after
      5000 -> raise "timeout"
    end

    assert [%Trans{text: "7"}] = PoolRepo.all(Trans)
  end

  ## Logging

  test "log begin, commit and rollback" do
    Process.put(:on_log, &send(self(), &1))
    PoolRepo.transaction(fn ->
      assert_received %Ecto.LogEntry{params: [], result: {:ok, _}} = entry
      assert is_integer(entry.query_time) and entry.query_time >= 0
      assert is_integer(entry.queue_time) and entry.queue_time >= 0

      refute_received %Ecto.LogEntry{}
      Process.put(:on_log, &send(self(), &1))
    end)

    assert_received %Ecto.LogEntry{params: [], result: {:ok, _}} = entry
    assert is_integer(entry.query_time) and entry.query_time >= 0
    assert is_nil(entry.queue_time)

    assert PoolRepo.transaction(fn ->
      refute_received %Ecto.LogEntry{}
      Process.put(:on_log, &send(self(), &1))
      PoolRepo.rollback(:log_rollback)
    end) == {:error, :log_rollback}
    assert_received %Ecto.LogEntry{params: [], result: {:ok, _}} = entry
    assert is_integer(entry.query_time) and entry.query_time >= 0
    assert is_nil(entry.queue_time)
  end

  test "log queries inside transactions" do
    PoolRepo.transaction(fn ->
      Process.put(:on_log, &send(self(), &1))
      assert [] = PoolRepo.all(Trans)

      assert_received %Ecto.LogEntry{params: [], result: {:ok, _}} = entry
      assert is_integer(entry.query_time) and entry.query_time >= 0
      assert is_integer(entry.decode_time) and entry.query_time >= 0
      assert is_nil(entry.queue_time)
    end)
  end

  @tag :strict_savepoint
  test "log raises after begin, drops transaction" do
    try do
      Process.put(:on_log, fn _ -> raise UniqueError end)
      PoolRepo.transaction(fn -> :ok end)
    rescue
      UniqueError -> :ok
    end

    # If it doesn't fail, the transaction was not closed properly.
    catch_error(PoolRepo.query!("savepoint foobar"))
  end

  test "log raises after begin, drops the whole transaction" do
    try do
      PoolRepo.transaction(fn ->
        PoolRepo.insert!(%Trans{text: "8"})
        Process.put(:on_log, fn _ -> raise UniqueError end)
        PoolRepo.transaction(fn -> flunk "log did not raise" end)
      end)
    rescue
      UniqueError -> :ok
    end

    assert [] = PoolRepo.all(Trans)
  end

  test "log raises after commit, does commit" do
    try do
      PoolRepo.transaction(fn ->
        PoolRepo.insert!(%Trans{text: "10"})
        Process.put(:on_log, fn _ -> raise UniqueError end)
      end)
    rescue
      UniqueError -> :ok
    end

    assert [%Trans{text: "10"}] = PoolRepo.all(Trans)
  end

  test "log raises after rollback, does rollback" do
    try do
      PoolRepo.transaction(fn ->
        PoolRepo.insert!(%Trans{text: "11"})
        Process.put(:on_log, fn _ -> raise UniqueError end)
        PoolRepo.rollback(:rollback)
      end)
    rescue
      UniqueError -> :ok
    end

    assert [] = PoolRepo.all(Trans)
  end
end
