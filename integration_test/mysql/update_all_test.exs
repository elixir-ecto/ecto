Code.require_file "../support/types.exs", __DIR__

defmodule Ecto.Integration.UpdateAllTest do
  use Ecto.Integration.Case

  alias Ecto.Integration.TestRepo
  import Ecto.Query

  alias Ecto.Integration.Post
  alias Ecto.Integration.Comment
  alias Ecto.Integration.User

  test "update_all" do
    user = TestRepo.insert!(%User{name: "Tester"})
    post = TestRepo.insert!(%Post{title: "foo"})
    TestRepo.insert!(%Comment{text: "hey", author_id: user.id, post_id: post.id})

    query = from(c in Comment, join: p in Post, on: p.id == c.post_id)

    assert {1, nil} = TestRepo.update_all(query, set: [text: "test"])
  end
end
