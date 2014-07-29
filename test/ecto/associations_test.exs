defmodule Ecto.AssociationsTest do
  use ExUnit.Case, async: true

  defmodule Post do
    use Ecto.Model

    schema "posts" do
      has_many :comments, Ecto.AssociationsTest.Comment
      has_one :permalink, Ecto.AssociationsTest.Permalink
    end
  end

  defmodule Comment do
    use Ecto.Model

    schema "comments" do
      field :text, :string
      belongs_to :post, Ecto.AssociationsTest.Post
    end
  end

  defmodule Permalink do
    use Ecto.Model

    schema "permalinks" do
      field :url, :string
      belongs_to :post, Ecto.AssociationsTest.Post
    end
  end

  test "has_many new" do
    post = Ecto.Model.put_primary_key(%Post{}, 42)
    assert %Comment{text: "heyo", post_id: 42} = struct(post.comments, text: "heyo")
  end

  test "has_one new" do
    post = Ecto.Model.put_primary_key(%Post{}, 42)
    assert %Permalink{url: "test", post_id: 42} = struct(post.permalink, url: "test")
  end

  test "load association" do
    post = %Post{}
    post = Ecto.Associations.load(post, :comments, [:test])
    assert [:test] = post.comments.all

    post = %Post{}
    post = Ecto.Associations.load(post, :permalink, :test)
    assert :test = post.permalink.get

    comment = %Comment{}
    comment = Ecto.Associations.load(comment, :post, :test)
    assert :test = comment.post.get
  end

  test "loading belongs_to sets foreign key" do
    post = %Post{id: 42}
    comment = %Comment{}
    comment = Ecto.Associations.load(comment, :post, post)
    assert comment.post_id == 42
  end
end
