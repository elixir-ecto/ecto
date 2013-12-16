defmodule Ecto.Query.NormalizerTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto.Query.Normalizer, only: [normalize: 1]

  alias Ecto.Query.JoinExpr

  defmodule Post do
    use Ecto.Model

    queryable :posts do
      field :title, :string
      field :text, :string
      has_many :comments, Ecto.Query.ValidatorTest.Comment
    end
  end

  test "auto select entity" do
    query = from(Post) |> normalize
    assert { :&, _, [0] } = query.select.expr
  end

  test "group by all fields" do
    query = from(p in Post, group_by: p) |> normalize
    var = { :&, [], [0] }
    assert [{ var, :id }, { var, :title }, { var, :text }] = Enum.first(query.group_bys).expr
  end

  test "normalize assoc joins" do
    query = from(p in Post, join: p.comments) |> normalize
    assert JoinExpr[on: on, assoc: assoc] = hd(query.joins)
    assert assoc == {{:&, [], [0]}, :comments}
    assert Macro.to_string(on.expr) == "&1.post_id() == &0.id()"
  end

  test "normalize assoc joins with on" do
    query = from(p in Post, join: c in p.comments, on: c.text == "") |> normalize
    assert JoinExpr[on: on] = hd(query.joins)
    assert Macro.to_string(on.expr) == "&1.text() == \"\" and &1.post_id() == &0.id()"
  end

  test "normalize joins: cannot associate without entity" do
    query = from(p in "posts", join: p.comments)
    assert_raise Ecto.QueryError, fn ->
      normalize(query)
    end
  end

  test "normalize joins: requires an association field" do
    query = from(p in Post, join: p.title)
    assert_raise Ecto.QueryError, fn ->
      normalize(query)
    end
  end
end
