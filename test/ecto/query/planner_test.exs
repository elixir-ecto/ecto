Code.require_file "../../support/types.exs", __DIR__

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
      field :posted, Ecto.DateTime
      belongs_to :post, Ecto.Query.PlannerTest.Post
      has_many :post_comments, through: [:post, :comments]
    end
  end

  defmodule Post do
    use Ecto.Model

    @primary_key {:id, Custom.Permalink, []}
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
        left_join: d in assoc(p, :comments),
        where: p.title == ^"2",
        group_by: p.title == ^"3",
        having: p.title == ^"4",
        order_by: [asc: fragment("?", ^"5")],
        limit: ^6,
        offset: ^7,
        preload: [post: d]

    {_query, params} = prepare(query)
    assert params == %{0 => "0", 1 => "1", 2 => "2", 3 => "3", 4 => "4",
                       5 => "5", 6 => 6, 7 => 7}
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

    exception = assert_raise Ecto.CastError, fn ->
      prepare(Post |> where([p], p.title == ^1))
    end

    assert Exception.message(exception) =~ "value `1` in `where` cannot be cast to type :string"
    assert Exception.message(exception) =~ "where: p.title == ^1"
    assert Exception.message(exception) =~ "Error when casting value to `#{inspect Post}.title`"
  end

  test "prepare: casts and dumps custom types" do
    datetime = %Ecto.DateTime{year: 2015, month: 1, day: 7, hour: 21, min: 18, sec: 13}
    {_query, params} = prepare(Comment |> where([c], c.posted == ^datetime))
    assert params[0] == {{2015, 1, 7}, {21, 18, 13}}

    permalink = "1-hello-world"
    {_query, params} = prepare(Post |> where([p], p.id == ^permalink))
    assert params[0] == 1
  end

  test "prepare: casts and dumps custom types with arrays" do
    datetime = %Ecto.DateTime{year: 2015, month: 1, day: 7, hour: 21, min: 18, sec: 13}
    {_query, params} = prepare(Comment |> where([c], c.posted in ^[datetime]))
    assert params[0] == [{{2015, 1, 7}, {21, 18, 13}}]

    permalink = "1-hello-world"
    {_query, params} = prepare(Post |> where([p], p.id in ^[permalink]))
    assert params[0] == [1]
  end

  test "prepare: joins" do
    query = from(p in Post, join: c in "comments") |> prepare |> elem(0)
    assert hd(query.joins).source == {"comments", nil}

    query = from(p in Post, join: c in Comment) |> prepare |> elem(0)
    assert hd(query.joins).source == {"comments", Comment}
  end

  test "prepare: joins associations" do
    query = from(p in Post, join: assoc(p, :comments)) |> prepare |> elem(0)
    assert %JoinExpr{on: on, source: source, assoc: nil, qual: :inner} = hd(query.joins)
    assert source == {"comments", Comment}
    assert Macro.to_string(on.expr) == "&1.post_id() == &0.id()"

    query = from(p in Post, left_join: assoc(p, :comments)) |> prepare |> elem(0)
    assert %JoinExpr{on: on, source: source, assoc: nil, qual: :left} = hd(query.joins)
    assert source == {"comments", Comment}
    assert Macro.to_string(on.expr) == "&1.post_id() == &0.id()"
  end

  test "prepare: nested joins associations" do
    query = from(c in Comment, left_join: assoc(c, :post_comments)) |> prepare |> elem(0)
    assert {{"comments", _}, {"comments", _}, {"posts", _}} = query.sources
    assert [join1, join2] = query.joins
    assert Enum.map(query.joins, & &1.ix) == [2, 1]
    assert Macro.to_string(join1.on.expr) == "&2.id() == &0.post_id()"
    assert Macro.to_string(join2.on.expr) == "&1.post_id() == &2.id()"

    query = from(p in Comment, left_join: assoc(p, :post),
                               left_join: assoc(p, :post_comments)) |> prepare |> elem(0)
    assert {{"comments", _}, {"posts", _}, {"comments", _}, {"posts", _}} = query.sources
    assert [join1, join2, join3] = query.joins
    assert Enum.map(query.joins, & &1.ix) == [1, 3, 2]
    assert Macro.to_string(join1.on.expr) == "&1.id() == &0.post_id()"
    assert Macro.to_string(join2.on.expr) == "&3.id() == &0.post_id()"
    assert Macro.to_string(join3.on.expr) == "&2.post_id() == &3.id()"

    query = from(p in Comment, left_join: assoc(p, :post_comments),
                               left_join: assoc(p, :post)) |> prepare |> elem(0)
    assert {{"comments", _}, {"comments", _}, {"posts", _}, {"posts", _}} = query.sources
    assert [join1, join2, join3] = query.joins
    assert Enum.map(query.joins, & &1.ix) == [3, 1, 2]
    assert Macro.to_string(join1.on.expr) == "&3.id() == &0.post_id()"
    assert Macro.to_string(join2.on.expr) == "&1.post_id() == &3.id()"
    assert Macro.to_string(join3.on.expr) == "&2.id() == &0.post_id()"
  end

  test "prepare: cannot associate without model" do
    query   = from(p in "posts", join: assoc(p, :comments))
    message = ~r"cannot perform association join on \"posts\" because it does not have a model"

    assert_raise Ecto.QueryError, message, fn ->
      prepare(query)
    end
  end

  test "prepare: requires an association field" do
    query = from(p in Post, join: assoc(p, :title))

    assert_raise Ecto.QueryError, ~r"could not find association `title`", fn ->
      prepare(query)
    end
  end

  test "prepare: tagged types" do
    {query, params} = from(Post, []) |> select([p], type(^"1", :integer)) |> prepare
    assert query.select.expr ==
           %Ecto.Query.Tagged{type: :integer, value: {:^, [], [0]}, tag: :integer}
    assert params == %{0 => 1}

    {query, params} = from(Post, []) |> select([p], type(^"1", Custom.Permalink)) |> prepare
    assert query.select.expr ==
           %Ecto.Query.Tagged{type: :integer, value: {:^, [], [0]}, tag: Custom.Permalink}
    assert params == %{0 => 1}

    assert_raise Ecto.QueryError, fn ->
      from(Post, []) |> select([p], type(^"1", :datetime)) |> prepare
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

  test "normalize: validate fields with custom types" do
    query = from(Post, []) |> where([p], p.id in [1,2,3])
    normalize(query)

    message = ~r"field `Ecto.Query.PlannerTest.Comment.text` in `where` does not type check"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(Comment, []) |> where([c], c.text in [1,2,3])
      normalize(query)
    end
  end

  test "normalize: select" do
    query = from(Post, []) |> normalize()
    assert query.select.expr == {:&, [], [0]}
    assert query.select.fields == [{:&, [], [0]}]

    query = from(Post, []) |> select([p], {p, p.title}) |> normalize()
    assert query.select.fields ==
           [{:&, [], [0]}, {{:., [], [{:&, [], [0]}, :title]}, [ecto_tag: :string], []}]

    query = from(Post, []) |> select([p], {p.title, p}) |> normalize()
    assert query.select.fields ==
           [{:&, [], [0]}, {{:., [], [{:&, [], [0]}, :title]}, [ecto_tag: :string], []}]

    query =
      from(Post, [])
      |> join(:inner, [_], c in Comment)
      |> preload([_, c], comments: c)
      |> select([p, _], {p.title, p})
      |> normalize()
    assert query.select.fields ==
           [{:&, [], [0]}, {:&, [], [1]},
            {{:., [], [{:&, [], [0]}, :title]}, [ecto_tag: :string], []}]
  end

  test "normalize: select without models" do
    message = ~r"queries with a string source \(\"posts\"\) expect an explicit select clause"
    assert_raise Ecto.QueryError, message, fn ->
      from(p in "posts") |> normalize()
    end

    message = ~r"cannot `select` or `preload` \"posts\" because it does not have a model"
    assert_raise Ecto.QueryError, message, fn ->
      from(p in "posts", select: p) |> normalize()
    end

    assert_raise Ecto.QueryError, message, fn ->
      from("comments", []) |> join(:inner, [c], p in "posts") |> select([c, p], p) |> normalize()
    end
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

  test "normalize: preload" do
    message = ~r"the binding used in `from` must be selected in `select` when using `preload`"
    assert_raise Ecto.QueryError, message, fn ->
      Post |> preload(:hello) |> select([p], p.title) |> normalize
    end
  end

  test "normalize: preload assoc" do
    query = from(p in Post, join: c in assoc(p, :comments), preload: [comments: c])
    normalize(query)

    message = ~r"field `Ecto.Query.PlannerTest.Post.not_field` in preload is not an association"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(p in Post, join: c in assoc(p, :comments), preload: [not_field: c])
      normalize(query)
    end

    message = ~r"requires an inner or left join, got right join"
    assert_raise Ecto.QueryError, message, fn ->
      query = from(p in Post, right_join: c in assoc(p, :comments), preload: [comments: c])
      normalize(query)
    end
  end
end
