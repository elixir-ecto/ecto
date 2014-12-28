defmodule Ecto.Query.PlannerTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Query.Planner
  alias Ecto.Query.JoinExpr

  defmodule Comment do
    use Ecto.Model

    schema "comments" do
      field :text, :string
      field :temp, :string, virtual: true
      field :posted, :datetime
      belongs_to :post, Ecto.Query.PlannerTest.Post
    end
  end

  defmodule Post do
    use Ecto.Model

    schema "posts" do
      field :title, :string
      field :text, :string
      has_many :comments, Ecto.Query.PlannerTest.Comment
    end
  end

  defp prepare(query, params \\ %{}) do
    Planner.prepare(query, params)
  end

  defp normalize(query, params \\ %{}, opts \\ []) do
    {query, params} = prepare(query, params)
    Planner.normalize(query, params, opts)
  end

  test "prepare: merges all parameters" do
    query =
      from p in Post,
        select: {p.title, ^"0"},
        join: c in Comment,
        on: c.text == ^"1",
        join: d in assoc(p, :comments),
        where: p.title == ^"2",
        group_by: p.title == ^"3",
        having: p.title == ^"4",
        order_by: [asc: ^"5"],
        limit: ^6,
        offset: ^7

    {query, params} = prepare(query)

    assert params == %{0 => "0", 1 => "1", 2 => "2", 3 => "3", 4 => "4",
                       5 => "5", 6 => 6, 7 => 7}

    assert query.select.params == nil
    refute Enum.any?(query.wheres, & &1.params)
    refute Enum.any?(query.group_bys, & &1.params)
  end

  test "prepare: checks from" do
    assert_raise Ecto.QueryError, ~r"query must have a from expression", fn ->
      prepare(%Ecto.Query{})
    end
  end

  test "prepare: casts values" do
    {_query, params} = prepare(Post |> where([p], p.id == ^"1"))
    assert params[0] == 1

    exception = assert_raise Ecto.CastError, fn ->
      prepare(Post |> where([p], p.title == ^nil))
    end

    assert Exception.message(exception) =~ "value `nil` in `where` cannot be cast to type :string"
    assert Exception.message(exception) =~ "where: p.title == ^nil"
    assert Exception.message(exception) =~ "Error when casting value to `#{inspect Post}.title`"

    exception =  assert_raise Ecto.CastError, fn ->
      prepare(Post |> where([p], p.title == ^1))
    end

    assert Exception.message(exception) =~ "value `1` in `where` cannot be cast to type :string"
    assert Exception.message(exception) =~ "where: p.title == ^1"
    assert Exception.message(exception) =~ "Error when casting value to `#{inspect Post}.title`"
  end

  test "prepare: joins" do
    query = from(p in Post, join: c in "comments") |> prepare |> elem(0)
    assert hd(query.joins).source == {"comments", nil}

    query = from(p in Post, join: c in Comment) |> prepare |> elem(0)
    assert hd(query.joins).source == {"comments", Comment}
  end

  test "prepare: joins associations" do
    query = from(p in Post, join: assoc(p, :comments)) |> prepare |> elem(0)
    assert %JoinExpr{on: on, source: source, assoc: assoc} = hd(query.joins)
    assert assoc == {0, :comments}
    assert source == {"comments", Comment}
    assert Macro.to_string(on.expr) == "&1.post_id() == &0.id()"
  end

  test "prepare: joins associations with on" do
    query = from(p in Post, join: c in assoc(p, :comments), on: c.text == "") |> prepare |> elem(0)
    assert %JoinExpr{on: on} = hd(query.joins)
    assert Macro.to_string(on.expr) == "&1.text() == \"\" and &1.post_id() == &0.id()"
  end

  test "prepare: cannot associate without model" do
    query = from(p in "posts", join: assoc(p, :comments))
    assert_raise Ecto.QueryError, ~r"association join cannot be performed without a model", fn ->
      prepare(query)
    end
  end

  test "prepare: requires an association field" do
    query = from(p in Post, join: assoc(p, :title))

    assert_raise Ecto.QueryError, ~r"could not find association `title`", fn ->
      prepare(query)
    end
  end

  test "normalize: validate fields" do
    message = ~r"field `Ecto.Query.PlannerTest.Comment.temp` in `select` does not exist in the model source"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(Comment, []) |> select([c], c.temp)
      normalize(query)
    end

    message = ~r"field `Ecto.Query.PlannerTest.Comment.text` in `where` does not type check"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(Comment, []) |> where([c], c.text)
      normalize(query)
    end
  end

  test "normalize: select" do
    query = from(Post, []) |> normalize()
    assert {:&, _, [0]} = query.select.expr
  end

  test "normalize: only where" do
    query = from(Post, []) |> normalize(%{}, only_where: true)
    assert is_nil query.select

    message = ~r"only `where` expressions are allowed in query"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(p in Post, select: p)
      normalize(query, %{}, only_where: true)
    end
  end

  test "normalize: assoc selector" do
    query = from(p in Post, join: c in assoc(p, :comments), select: assoc(p, comments: c))
    normalize(query)

    query = from(p in Post, join: c in assoc(p, :comments), select: assoc(c, post: p))
    normalize(query)

    message = ~r"field `Ecto.Query.PlannerTest.Post.not_field` in assoc/2 is not an association"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(p in Post, join: c in assoc(p, :comments), select: assoc(p, not_field: c))
      normalize(query)
    end

    message = ~r"association `Ecto.Query.PlannerTest.Post.comments` in assoc/2 doesn't match join model"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(p in Post, join: c in Post, select: assoc(p, comments: c))
      normalize(query)
    end

    message = ~r"requires an inner or left join, got right join"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(p in Post, right_join: c in assoc(p, :comments), select: assoc(p, comments: c))
      normalize(query)
    end
  end
end
