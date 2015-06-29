Code.require_file "../../support/mock_repo.exs", __DIR__
alias Ecto.MockRepo

defmodule Ecto.Model.DependentTest do
  use ExUnit.Case, async: true

  defmodule Post do
    use Ecto.Model
    alias Ecto.Model.DependentTest.Comment

    schema "dependent_posts" do
      has_many :comments, Comment, dependent: :delete_all
    end
  end

  defmodule Comment do
    use Ecto.Model
    alias Ecto.Model.DependentTest.Post

    schema "dependent_comments" do
      belongs_to :post, Post
    end

    before_delete :callback_check, []

    def callback_check(changeset) do
      hits = Process.get(:callback_check) || []
      Process.put(:callback_check, [changeset.model.id|hits])
      changeset
    end
  end

  test "delete_all deletes dependent w/o triggering callbacks" do
    post = MockRepo.insert!(%Post{id: 1}, struct: Post)
    MockRepo.insert!(%Comment{id: 1, post_id: post.id}, struct: Comment)
    MockRepo.insert!(%Comment{id: 2, post_id: post.id}, struct: Comment)

    comments = MockRepo.all(Comment)
    assert Enum.count(comments) == 2

    MockRepo.delete!(post)
    comments = MockRepo.all(Comment)
    assert Enum.count(comments) == 0

    assert Process.get(:callback_check) == nil
  end

  defmodule Picture do
    use Ecto.Model
    alias Ecto.Model.DependentTest.Like

    schema "dependent_pictures" do
      has_many :likes, Like, dependent: :fetch_and_delete
    end
  end

  defmodule Like do
    use Ecto.Model
    alias Ecto.Model.DependentTest.Picture

    schema "dependent_likes" do
      belongs_to :picture, Picture
    end

    before_delete :callback_check, []

    def callback_check(changeset) do
      hits = Process.get(:callback_check) || []
      Process.put(:callback_check, [changeset.model.id|hits])
      changeset
    end
  end

  test "fetch_and_delete deletes dependents and triggers callbacks" do
    picture = MockRepo.insert!(%Picture{id: 1}, struct: Picture)
    MockRepo.insert!(%Like{id: 1, picture_id: picture.id}, struct: Like)
    MockRepo.insert!(%Like{id: 2, picture_id: picture.id}, struct: Like)

    likes = MockRepo.all(Like)
    assert Enum.count(likes) == 2

    MockRepo.delete!(picture)
    likes = MockRepo.all(Like)
    assert Enum.count(likes) == 0

    assert Process.get(:callback_check) == [1, 2]
  end

  defmodule User do
    use Ecto.Model
    alias Ecto.Model.DependentTest.Role

    schema "dependent_users" do
      has_many :roles, Role, dependent: :nilify_all
    end
  end

  defmodule Role do
    use Ecto.Model
    alias Ecto.Model.DependentTest.User

    schema "dependent_roles" do
      belongs_to :user, User
    end
  end

  test "nilify_all sets foreign keys on dependents to nil w/o triggering callbacks" do
    user = MockRepo.insert!(%User{id: 1}, struct: User)
    MockRepo.insert!(%Role{id: 1, user_id: user.id}, struct: Role)
    MockRepo.insert!(%Role{id: 2, user_id: user.id}, struct: Role)

    roles = MockRepo.all(Role)
    assert Enum.count(roles) == 2

    MockRepo.delete!(user)
    roles = MockRepo.all(Role)
    for role <- roles do
      assert is_nil(role.user_id)
    end
  end
end
