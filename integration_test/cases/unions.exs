defmodule Ecto.Integration.UnionsTest do
  use Ecto.Integration.Case, async: Application.get_env(:ecto, :async_integration_tests, true)

  alias Ecto.Integration.TestRepo
  import Ecto.Query

  alias Ecto.Integration.Custom
  alias Ecto.Integration.Post
  alias Ecto.Integration.User
  alias Ecto.Integration.PostUser
  alias Ecto.Integration.Comment
  alias Ecto.Integration.Permalink

  test "ecto bug test" do
    TestRepo.insert!(%Post{})
    TestRepo.insert!(%Post{})

    # Insert one role
    query1 = from(p in Post, select: %{n: 1})
    query2 = from(p in Post, select: %{n: 2})

    # This assertion fails
    assert TestRepo.all(union(query1, ^query2)) == [%{n: 1}, %{n: 2}]
  end
end
