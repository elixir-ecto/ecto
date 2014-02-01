defmodule Ecto.Integration.TransactionTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  alias Ecto.Adapters.Postgres

  defmodule TestRepo1 do
    use Ecto.Repo, adapter: Postgres

    def url do
      "ecto://postgres:postgres@localhost/ecto_test?size=10"
    end
  end

  defmodule TestRepo2 do
    use Ecto.Repo, adapter: Postgres

    def url do
      "ecto://postgres:postgres@localhost/ecto_test?size=1&max_overflow=0"
    end
  end

  defexception UniqueError, [:message]

  setup_all do
    { :ok, _ } = TestRepo1.start_link
    { :ok, _ } = TestRepo2.start_link
    :ok
  end

  teardown_all do
    :ok = TestRepo1.stop
    :ok = TestRepo2.stop
  end

  setup do
    Postgres.query(TestRepo1, "DELETE FROM transaction")
    :ok
  end

  defmodule Trans do
    use Ecto.Model

    queryable "transaction" do
      field :text, :string
    end
  end

  test "transaction returns value" do
    x = TestRepo1.transaction(fn ->
      TestRepo1.transaction(fn ->
        42
      end)
    end)
    assert x == { :ok, { :ok, 42 } }
  end

  test "transaction re-raises" do
    assert_raise UniqueError, fn ->
      TestRepo1.transaction(fn ->
        TestRepo1.transaction(fn ->
          raise UniqueError[]
        end)
      end)
    end
  end

  test "transaction commits" do
    TestRepo1.transaction(fn ->
      e = TestRepo1.create(Trans.Entity[text: "1"])
      assert [^e] = TestRepo1.all(Trans)
      assert [] = TestRepo2.all(Trans)
    end)

    assert [Trans.Entity[text: "1"]] = TestRepo2.all(Trans)
  end

  test "transaction rolls back" do
    try do
      TestRepo1.transaction(fn ->
        e = TestRepo1.create(Trans.Entity[text: "2"])
        assert [^e] = TestRepo1.all(Trans)
        assert [] = TestRepo2.all(Trans)
        raise UniqueError[]
      end)
    rescue
      UniqueError -> :ok
    end

    assert [] = TestRepo2.all(Trans)
  end

  test "nested transaction partial roll back" do
    TestRepo1.transaction(fn ->
      e1 = TestRepo1.create(Trans.Entity[text: "3"])
      assert [^e1] = TestRepo1.all(Trans)

        try do
          TestRepo1.transaction(fn ->
            e2 = TestRepo1.create(Trans.Entity[text: "4"])
            assert [^e1, ^e2] = TestRepo1.all(from(t in Trans, order_by: t.text))
            raise UniqueError[]
          end)
        rescue
          UniqueError -> :ok
        end

      e3 = TestRepo1.create(Trans.Entity[text: "5"])
      assert [^e1, ^e3] = TestRepo1.all(from(t in Trans, order_by: t.text))
      assert [] = TestRepo2.all(Trans)
      end)

    assert [Trans.Entity[text: "3"], Trans.Entity[text: "5"]] = TestRepo2.all(from(t in Trans, order_by: t.text))
  end

  test "manual rollback doesnt bubble up" do
    x = TestRepo1.transaction(fn ->
      e = TestRepo1.create(Trans.Entity[text: "6"])
      assert [^e] = TestRepo1.all(Trans)
      throw :ecto_rollback
    end)

    assert x == :error
    assert [] = TestRepo2.all(Trans)
  end

  test "manual rollback with term" do
    x = TestRepo1.transaction(fn ->
      e = TestRepo1.create(Trans.Entity[text: "6"])
      assert [^e] = TestRepo1.all(Trans)
      throw { :ecto_rollback, "ecto" }
    end)

    assert x == { :error, "ecto" }
    assert [] = TestRepo2.all(Trans)
  end

  test "transactions are not shared in repo" do
    pid = self

    new_pid = spawn_link fn ->
      TestRepo1.transaction(fn ->
        e = TestRepo1.create(Trans.Entity[text: "7"])
        assert [^e] = TestRepo1.all(Trans)
        send(pid, :in_transaction)
        receive do
          :commit -> :ok
        after
          5000 -> raise "timeout"
        end
      end)
      send(pid, :commited)
    end

    receive do
      :in_transaction -> :ok
    after
      5000 -> raise "timeout"
    end
    assert [] = TestRepo1.all(Trans)

    send(new_pid, :commit)
    receive do
      :commited -> :ok
    after
      5000 -> raise "timeout"
    end

    assert [Trans.Entity[text: "7"]] = TestRepo1.all(Trans)
  end
end
