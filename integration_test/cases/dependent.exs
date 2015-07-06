defmodule Ecto.Integration.DependentTest do
  use Ecto.Integration.Case

  require Ecto.Integration.TestRepo, as: TestRepo

  alias Ecto.Integration.Post
  alias Ecto.Integration.Comment
  alias Ecto.Integration.Permalink
  alias Ecto.Integration.User

  def callback_triggered?, do: Process.get(:callback_check)

  setup do
    Process.put(:callback_check, false)
    :ok
  end

  test "delete all" do
    post = TestRepo.insert!(%Post{})
    TestRepo.insert!(%Comment{post_id: post.id})
    TestRepo.insert!(%Comment{post_id: post.id})
    TestRepo.delete!(post)

    assert TestRepo.all(Comment) == []
    refute callback_triggered?
  end

  test "fetch and delete" do
    post = TestRepo.insert!(%Post{})
    TestRepo.insert!(%Permalink{post_id: post.id})
    TestRepo.delete!(post)

    assert TestRepo.all(Permalink) == []
    assert callback_triggered?
  end

  test "nilify all" do
    user = TestRepo.insert!(%User{})
    TestRepo.insert!(%Comment{author_id: user.id})
    TestRepo.insert!(%Comment{author_id: user.id})
    TestRepo.delete!(user)

    author_ids = Comment |> TestRepo.all() |> Enum.map(fn(comment) -> comment.author_id end)

    assert author_ids == [nil, nil]
    refute callback_triggered?
  end

  test "nothing" do
    user = TestRepo.insert!(%User{})
    TestRepo.insert!(%Post{author_id: user.id})

    TestRepo.delete!(user)
    assert Enum.count(TestRepo.all(Post)) == 1
  end
end
