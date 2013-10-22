defmodule Ecto.AssociationsTest do
  use Ecto.TestCase, async: true

  defmodule Post do
    use Ecto.Model

    queryable "posts" do
      has_many :comments, Ecto.AssociationsTest.Comment
      has_one :permalink, Ecto.AssociationsTest.Permalink
    end
  end

  defmodule Comment do
    use Ecto.Model

    queryable "comments" do
      field :text, :string
      belongs_to :post, Ecto.AssociationsTest.Post
    end
  end

  defmodule Permalink do
    use Ecto.Model

    queryable "permalinks" do
      field :url, :string
      belongs_to :post, Ecto.AssociationsTest.Post
    end
  end

  test "has_many new" do
    post = Post.new(id: 42)
    assert Comment.Entity[text: "heyo", post_id: 42] = post.comments.new(text: "heyo")
  end

  test "has_one new" do
    post = Post.new(id: 42)
    assert Permalink.Entity[url: "test", post_id: 42] = post.permalink.new(url: "test")
  end
end
