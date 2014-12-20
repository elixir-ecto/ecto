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

  test "prepare: merges all parameters" do
    query =
      from p in Post,
        select: {p.title, ^0},
        join: c in Comment,
        on: c.text == ^1,
        join: c in p.comments,
        where: p.title == ^2,
        group_by: p.title == ^3,
        having: p.title == ^4,
        order_by: [asc: ^5],
        limit: ^6,
        offset: ^7

    {query, params} = prepare(query)

    assert params == %{0 => 0, 1 => 1, 2 => 2, 3 => 3, 4 => 4,
                       5 => 5, 6 => 6, 7 => 7}

    assert query.select.params == nil
    refute Enum.any?(query.where, & &1.params)
    refute Enum.any?(query.group_by, & &1.params)
  end

  test "prepare: checks from" do
    assert_raise Ecto.QueryError, ~r"query must have a from expression", fn ->
      normalize(%Ecto.Query{})
    end
  end

  test "prepare: joins" do
    query = from(p in Post, join: c in "comments") |> prepare |> elem(0)
    assert hd(query.joins).source == {"comments", nil}

    query = from(p in Post, join: c in Comment) |> prepare |> elem(0)
    assert hd(query.joins).source == {"comments", Comment}
  end

  test "prepare: joins associations" do
    query = from(p in Post, join: p.comments) |> prepare |> elem(0)
    assert %JoinExpr{on: on, source: source, assoc: assoc} = hd(query.joins)
    assert assoc == {0, :comments}
    assert source == {"comments", Comment}
    assert Macro.to_string(on.expr) == "&1.post_id() == &0.id()"
  end

  test "prepare: joins associations with on" do
    query = from(p in Post, join: c in p.comments, on: c.text == "") |> prepare |> elem(0)
    assert %JoinExpr{on: on} = hd(query.joins)
    assert Macro.to_string(on.expr) == "&1.text() == \"\" and &1.post_id() == &0.id()"
  end

  test "prepare: cannot associate without model" do
    query = from(p in "posts", join: p.comments)
    assert_raise Ecto.QueryError, ~r"association join cannot be performed without a model", fn ->
      prepare(query)
    end
  end

  test "prepare: requires an association field" do
    query = from(p in Post, join: p.title)

    assert_raise Ecto.QueryError, ~r"could not find association `title`", fn ->
      prepare(query)
    end
  end

  test "normalize: select" do
    query = from(Post, []) |> normalize
    assert {:&, _, [0]} = query.select.expr
  end
end
