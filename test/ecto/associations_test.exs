defmodule Ecto.AssociationsTest do
  use ExUnit.Case, async: true
  doctest Ecto.Associations

  import Ecto.Model
  import Ecto.Query, only: [from: 2]

  alias __MODULE__.Post
  alias __MODULE__.Comment
  alias __MODULE__.Permalink

  defmodule Post do
    use Ecto.Model

    schema "posts" do
      has_many :comments, Comment
      has_one  :permalink, Permalink
    end
  end

  defmodule Comment do
    use Ecto.Model

    schema "posts" do
      belongs_to :post, Post
    end
  end

  defmodule Permalink do
    use Ecto.Model

    schema "posts" do
      belongs_to :post, Post
    end
  end

  ## Unit tests

  test "has many" do
    assoc = Post.__schema__(:association, :comments)

    assert inspect(Ecto.Associations.Has.joins_query(assoc)) ==
           inspect(from c in Comment, join: p in Post, on: c.post_id == p.id)

    assert inspect(Ecto.Associations.Has.assoc_query(assoc, [])) ==
           inspect(from c in Comment, where: c.post_id in ^[])

    assert inspect(Ecto.Associations.Has.assoc_query(assoc, [1, 2, 3])) ==
           inspect(from c in Comment, where: c.post_id in ^[1, 2, 3])
  end

  test "has one" do
    assoc = Post.__schema__(:association, :permalink)

    assert inspect(Ecto.Associations.Has.joins_query(assoc)) ==
           inspect(from c in Permalink, join: p in Post, on: c.post_id == p.id)

    assert inspect(Ecto.Associations.Has.assoc_query(assoc, [])) ==
           inspect(from c in Permalink, where: c.post_id in ^[])

    assert inspect(Ecto.Associations.Has.assoc_query(assoc, [1, 2, 3])) ==
           inspect(from c in Permalink, where: c.post_id in ^[1, 2, 3])
  end

  test "belongs to" do
    assoc = Permalink.__schema__(:association, :post)

    assert inspect(Ecto.Associations.Has.joins_query(assoc)) ==
           inspect(from p in Post, join: l in Permalink, on: p.id == l.post_id)

    assert inspect(Ecto.Associations.Has.assoc_query(assoc, [])) ==
           inspect(from p in Post, where: p.id in ^[])

    assert inspect(Ecto.Associations.Has.assoc_query(assoc, [1, 2, 3])) ==
           inspect(from p in Post, where: p.id in ^[1, 2, 3])
  end

  ## Integration tests through Ecto.Model

  test "assoc/2" do
    assert inspect(assoc(%Post{id: 1}, :comments)) ==
           inspect(from c in Comment, where: c.post_id in ^[1])

    assert inspect(assoc([%Post{id: 1}, %Post{id: 2}], :comments)) ==
           inspect(from c in Comment, where: c.post_id in ^[1, 2])
  end

  test "assoc/2 filters nil ids" do
    assert inspect(assoc([%Post{id: 1}, %Post{id: 2}, %Post{}], :comments)) ==
           inspect(from c in Comment, where: c.post_id in ^[1, 2])
  end

  test "assoc/2 fails on empty list" do
    assert_raise ArgumentError, ~r"cannot retrieve association :whatever for empty list", fn ->
      assoc([], :whatever)
    end
  end

  test "assoc/2 fails on missing association" do
    assert_raise ArgumentError, ~r"does not have association :whatever", fn ->
      assoc([%Post{}], :whatever)
    end
  end

  test "assoc/2 fails on heterogeneous collections" do
    assert_raise ArgumentError, ~r"expected an homogeneous list containing the same struct", fn ->
      assoc([%Post{}, %Comment{}], :comments)
    end
  end
end
