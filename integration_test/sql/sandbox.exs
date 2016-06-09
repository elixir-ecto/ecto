defmodule Ecto.Integration.SandboxTest do
  use ExUnit.Case

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

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
end
