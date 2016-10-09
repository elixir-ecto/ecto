defmodule Ecto.Integration.SandboxTest do
  use ExUnit.Case

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  import ExUnit.CaptureLog

  test "include link to SQL sandbox on ownership errors" do
    assert_raise DBConnection.OwnershipError,
             ~r"See Ecto.Adapters.SQL.Sandbox docs for more information.", fn ->
      TestRepo.all(Post)
    end
  end

  test "can use the repository when checked out" do
    assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
      TestRepo.all(Post)
    end
    Sandbox.checkout(TestRepo)
    assert TestRepo.all(Post) == []
    Sandbox.checkin(TestRepo)
    assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
      TestRepo.all(Post)
    end
  end

  test "can use the repository when allowed from another process" do
    assert_raise DBConnection.OwnershipError, ~r"cannot find ownership process", fn ->
      TestRepo.all(Post)
    end

    parent = self()
    Task.start_link fn ->
      Sandbox.checkout(TestRepo)
      Sandbox.allow(TestRepo, self(), parent)
      send parent, :allowed
      :timer.sleep(:infinity)
    end

    assert_receive :allowed
    assert TestRepo.all(Post) == []
  end

  test "can use the repository when shared from another process" do
    Sandbox.checkout(TestRepo)
    Sandbox.mode(TestRepo, {:shared, self()})
    assert Task.async(fn -> TestRepo.all(Post) end) |> Task.await == []
  after
    Sandbox.mode(TestRepo, :manual)
  end

  test "runs inside a sandbox that is rolled back on checkin" do
    Sandbox.checkout(TestRepo)
    assert TestRepo.insert(%Post{})
    assert TestRepo.all(Post) != []
    Sandbox.checkin(TestRepo)
    Sandbox.checkout(TestRepo)
    assert TestRepo.all(Post) == []
    Sandbox.checkin(TestRepo)
  end

  test "runs inside a sandbox that may be disabled" do
    Sandbox.checkout(TestRepo, sandbox: false)
    assert TestRepo.insert(%Post{})
    assert TestRepo.all(Post) != []
    Sandbox.checkin(TestRepo)

    Sandbox.checkout(TestRepo)
    assert {1, _} = TestRepo.delete_all(Post)
    Sandbox.checkin(TestRepo)

    Sandbox.checkout(TestRepo, sandbox: false)
    assert {1, _} = TestRepo.delete_all(Post)
    Sandbox.checkin(TestRepo)
  end

  @tag :transaction_isolation
  test "runs inside a sandbox with custom isolation level" do
    Sandbox.checkout(TestRepo, isolation: "READ UNCOMMITTED")

    # Setting it to the same level later on works
    TestRepo.query!("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED")

    # Even inside a transaction
    TestRepo.transaction fn ->
      TestRepo.query!("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED")
    end
  end

  test "disconnects sandbox on transaction timeouts" do
    Sandbox.checkout(TestRepo)

    assert capture_log(fn ->
      catch_error(
        TestRepo.transaction fn ->
          :timer.sleep(1000)
        end, timeout: 0
      )
    end) =~ "timed out"

    Sandbox.checkin(TestRepo)
  end

  test "runs inside a sandbox even with failed queries" do
    Sandbox.checkout(TestRepo)

    {:ok, _}    = TestRepo.insert(%Post{}, skip_transaction: true)
    # This is a failed query but it should not taint the sandbox transaction
    {:error, _} = TestRepo.query("INVALID")
    {:ok, _}    = TestRepo.insert(%Post{}, skip_transaction: true)

    Sandbox.checkin(TestRepo)
  end

  test "works when preloading associations from another process" do
    Sandbox.checkout(TestRepo)
    assert TestRepo.insert(%Post{})
    parent = self()

    Task.start_link fn ->
      Sandbox.allow(TestRepo, parent, self())
      assert [_] = TestRepo.all(Post) |> TestRepo.preload([:author, :comments])
      send parent, :success
    end

    assert_receive :success
  end

  test "allows an ownership timeout to be passed for an individual `checkout` call" do
    log = capture_log fn ->
      :ok = Sandbox.checkout(TestRepo, ownership_timeout: 20)

      Process.sleep(1000)

      assert_raise DBConnection.OwnershipError, fn ->
        TestRepo.all(Post)
      end
    end

    assert log =~ ~r/timed out.*20ms/
  end
end
