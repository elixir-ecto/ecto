defmodule Ecto.Query.NormalizerTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto.Query.Normalizer

  alias Ecto.Query.JoinExpr

  defmodule Comment do
    use Ecto.Model

    schema "comments" do
      field :text, :string
      field :temp, :string, virtual: true
      field :posted, :datetime
      belongs_to :post, Ecto.Query.NormalizerTest.Post
    end
  end

  defmodule Post do
    use Ecto.Model

    schema "posts" do
      field :title, :string
      field :text, :string
      has_many :comments, Ecto.Query.NormalizerTest.Comment
    end
  end

  test "auto select model" do
    query = from(Post, []) |> normalize
    assert {:&, _, [0]} = query.select.expr
  end

  test "normalizes from" do
    assert_raise Ecto.QueryError, ~r"a query must have a from expression", fn ->
      normalize(%Ecto.Query{})
    end
  end

  test "normalizes joins" do
    query = from(p in Post, join: c in "comments") |> normalize
    assert hd(query.joins).source == {"comments", nil}

    query = from(p in Post, join: c in Comment) |> normalize
    assert hd(query.joins).source == {"comments", Comment}
  end

  test "normalizes joins: associations" do
    query = from(p in Post, join: p.comments) |> normalize
    assert %JoinExpr{on: on, source: source, assoc: assoc} = hd(query.joins)
    assert assoc == {0, :comments}
    assert source == {"comments", Comment}
    assert Macro.to_string(on.expr) == "&1.post_id() == &0.id()"
  end

  test "normalizes joins: associations with on" do
    query = from(p in Post, join: c in p.comments, on: c.text == "") |> normalize
    assert %JoinExpr{on: on} = hd(query.joins)
    assert Macro.to_string(on.expr) == "&1.text() == \"\" and &1.post_id() == &0.id()"
  end

  test "normalizes joins: cannot associate without model" do
    query = from(p in "posts", join: p.comments)
    assert_raise Ecto.QueryError, ~r"association join cannot be performed without a model", fn ->
      normalize(query)
    end
  end

  test "normalizes joins: requires an association field" do
    query = from(p in Post, join: p.title)

    assert_raise Ecto.QueryError, ~r"could not find association `title`", fn ->
      normalize(query)
    end
  end
end
