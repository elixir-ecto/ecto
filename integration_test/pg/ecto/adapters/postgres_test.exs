Code.require_file "../../test_helper.exs", __DIR__

defmodule Ecto.Adapters.PostgresTest do
  use Ecto.PgTest.Case

  alias Ecto.PgTest.TestRepo
  alias Ecto.PgTest.Post
  import Ecto.Query

  test "fetch empty" do
    assert [] == TestRepo.fetch(from p in Post)
  end

  test "create and fetch single" do
    post = Post[id: 1, title: "The shiny new Ecto", text: "coming soon..."]

    assert post == TestRepo.create(Post.new(title: post.title, text: post.text))

    assert [post] == TestRepo.fetch(from p in Post)
  end
end
