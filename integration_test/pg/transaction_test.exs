defmodule Ecto.Integration.TransactionTest do
  # We can keep this test async as long as it
  # is the only one access the transactions table
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.Adapters.Postgres

  defmodule TestRepo1 do
    use Ecto.Repo, adapter: Postgres, otp_app: :ecto
  end

  Application.put_env(:ecto, TestRepo1,
    url: "ecto://postgres:postgres@localhost/ecto_test",
    size: 10)

  defmodule TestRepo2 do
    use Ecto.Repo, adapter: Postgres, otp_app: :ecto
  end

  Application.put_env(:ecto, TestRepo2,
    url: "ecto://postgres:postgres@localhost/ecto_test",
    size: 1,
    max_overflow: 0)

  defmodule UniqueError do
    defexception [:message]
  end

  setup_all do
    {:ok, _} = TestRepo1.start_link
    {:ok, _} = TestRepo2.start_link
    :ok
  end

  setup do
    TestRepo1.delete_all "transactions"
    :ok
  end

  defmodule Trans do
    use Ecto.Model

    schema "transactions" do
      field :text, :string
    end
  end

  test "transaction returns value" do
    x = TestRepo1.transaction(fn ->
      TestRepo1.transaction(fn ->
        42
      end)
    end)
    assert x == {:ok, {:ok, 42}}
  end

  test "transaction re-raises" do
    assert_raise UniqueError, fn ->
      TestRepo1.transaction(fn ->
        TestRepo1.transaction(fn ->
          raise UniqueError
        end)
      end)
    end
  end

  test "transaction commits" do
    TestRepo1.transaction(fn ->
      e = TestRepo1.insert(%Trans{text: "1"})
      assert [^e] = TestRepo1.all(Trans)
      assert [] = TestRepo2.all(Trans)
    end)

    assert [%Trans{text: "1"}] = TestRepo2.all(Trans)
  end

  test "transaction rolls back" do
    try do
      TestRepo1.transaction(fn ->
        e = TestRepo1.insert(%Trans{text: "2"})
        assert [^e] = TestRepo1.all(Trans)
        assert [] = TestRepo2.all(Trans)
        raise UniqueError
      end)
    rescue
      UniqueError -> :ok
    end

    assert [] = TestRepo2.all(Trans)
  end

  test "nested transaction partial roll back" do
    TestRepo1.transaction(fn ->
      e1 = TestRepo1.insert(%Trans{text: "3"})
      assert [^e1] = TestRepo1.all(Trans)

        try do
          TestRepo1.transaction(fn ->
            e2 = TestRepo1.insert(%Trans{text: "4"})
            assert [^e1, ^e2] = TestRepo1.all(from(t in Trans, order_by: t.text))
            raise UniqueError
          end)
        rescue
          UniqueError -> :ok
        end

      e3 = TestRepo1.insert(%Trans{text: "5"})
      assert [^e1, ^e3] = TestRepo1.all(from(t in Trans, order_by: t.text))
      assert [] = TestRepo2.all(Trans)
      end)

    assert [%Trans{text: "3"}, %Trans{text: "5"}] = TestRepo2.all(from(t in Trans, order_by: t.text))
  end

  test "manual rollback doesnt bubble up" do
    x = TestRepo1.transaction(fn ->
      e = TestRepo1.insert(%Trans{text: "6"})
      assert [^e] = TestRepo1.all(Trans)
      TestRepo1.rollback(:oops)
    end)

    assert x == {:error, :oops}
    assert [] = TestRepo2.all(Trans)
  end

  test "transactions are not shared in repo" do
    pid = self

    new_pid = spawn_link fn ->
      TestRepo1.transaction(fn ->
        e = TestRepo1.insert(%Trans{text: "7"})
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

    assert [%Trans{text: "7"}] = TestRepo1.all(Trans)
  end
end
