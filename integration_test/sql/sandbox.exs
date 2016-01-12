defmodule Ecto.Integration.SandboxTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  test "can only use the repository when checked out" do
    assert_raise RuntimeError, ~r"cannot find ownership process", fn ->
      TestRepo.all(Post)
    end
    Sandbox.checkout(TestRepo)
    assert TestRepo.all(Post) == []
    Sandbox.checkin(TestRepo)
    assert_raise RuntimeError, ~r"cannot find ownership process", fn ->
      TestRepo.all(Post)
    end
  end
end
