defmodule Ecto.Query.ValidatorTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.Query
  alias Ecto.Query.Normalizer
  alias Ecto.Query.Validator

  defmodule Post do
    use Ecto.Model

    schema :posts do
      field :title, :string
      field :text, :string
      has_many :comments, Ecto.Query.ValidatorTest.Comment
      has_one :permalink, Ecto.Query.ValidatorTest.Permalink
    end
  end

  defmodule Permalink do
    use Ecto.Model

    schema :comments, primary_key: false do
      belongs_to :post, Ecto.Query.ValidatorTest.Post
    end
  end

  defmodule Comment do
    use Ecto.Model

    schema :comments do
      field :text, :string
      field :temp, :virtual
      field :posted, :datetime
      field :day, :date
      field :time, :time
      belongs_to :post, Ecto.Query.ValidatorTest.Post
    end
  end

  def validate(query) do
    query
    |> Normalizer.normalize
    |> Validator.validate([Ecto.Query.API])
  end


  test "valid query with bindings" do
    query = Post |> select([p], {p.title})
    validate(query)

    query = "posts" |> select([p], {p.title})
    validate(query)
  end

  test "invalid query" do
    query = select(%Query{}, [], 123)
    assert_raise Ecto.QueryError, ~r"a query must have a from expression", fn ->
      validate(query)
    end
  end

  test "where expression must be boolean" do
    query = Post |> where([p], p.title == "") |> select([], 123)
    validate(query)

    query = "posts" |> where([p], p.title == "") |> select([], 123)
    validate(query)

    query = Post |> where([p], p.title) |> select([], 123)
    assert_raise Ecto.QueryError, ~r"where expression", fn ->
      validate(query)
    end
  end

  test "having expression must be boolean" do
    query = Post |> having([], "abc" == "") |> select([], 123)
    validate(query)

    query = Post |> having([], "abc") |> select([], 123)
    assert_raise Ecto.QueryError, ~r"having expression", fn ->
      validate(query)
    end
  end

  test "join expression must be boolean" do
    query = Post |> join(:inner, [], Comment, "abc" == "") |> select([], 123)
    validate(query)

    query = Post |> join(:inner, [], Comment, "abc") |> select([], 123)
    assert_raise Ecto.QueryError, ~r"join_on expression", fn ->
      validate(query)
    end
  end

  test "limit expression must be integer" do
    query = Post |> limit(40 + 2) |> select([], 123)
    validate(query)

    query = Post |> limit(42 > 0) |> select([], 123)
    assert_raise Ecto.QueryError, ~r"limit expression", fn ->
      validate(query)
    end
  end

  test "offset expression must be integer" do
    query = Post |> offset(40 + 2) |> select([], 123)
    validate(query)

    query = Post |> offset(42 > 0) |> select([], 123)
    assert_raise Ecto.QueryError, ~r"offset expression", fn ->
      validate(query)
    end
  end

  test "model field types" do
    query = Post |> select([p], p.title + 2)
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end
  end

  test "unknown field" do
    query = Post |> select([p], p.unknown)
    assert_raise Ecto.QueryError, ~r"unknown field `unknown` on `Ecto.Query.ValidatorTest.Post`", fn ->
      validate(query)
    end
  end

  test "valid expressions" do
    query = Post |> select([p], p.id + 2)
    validate(query)

    query = Post |> select([p], p.id == 2)
    validate(query)

    query = Post |> select([p], p.title == "abc")
    validate(query)

    query = Post |> select([], 1 + +123)
    validate(query)

    query = Post |> where([p], p.id < 10) |> select([], 0)
    validate(query)

    query = Post |> where([], true or false) |> select([], 0)
    validate(query)

    query = "posts" |> where([p], p.a or p.b + p.c * upcase(p.d)) |> select([], 0)
    validate(query)
  end

  test "invalid expressions" do
    query = Post |> select([p], p.id + "abc")
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end

    query = Post |> select([p], p.id == "abc")
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end

    query = Post |> select([p], -p.title)
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end

    query = Post |> select([p], 1 < p.title)
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end

    query = Post |> where([p], true or p.title) |> select([], 0)
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end
  end

  test "valid in expression" do
    query = Post |> select([], 1 in array([1,2,3], :integer))
    validate(query)

    query = Post |> select([], (2+2) in 1..5)
    validate(query)
  end

  test "invalid in expression" do
    query = Post |> select([p], 1 in p.title)
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end
  end

  test "valid .. expression" do
    query = Post |> select([], 1 .. 3)
    validate(query)
  end

  test "invalid .. expression" do
    query = Post |> select([], "1" .. 3)
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end
  end

  test "array expression" do
    query = Post |> where([p], array([p.title, p.title], :string) == nil) |> select([], 0)
    validate(query)

    query = Post |> where([p], array([p.title, p.title], :binary) == nil) |> select([], 0)
    validate(query)

    query = Post |> where([p], [p.title, p.title] == nil) |> select([], 0)
    assert_raise Ecto.QueryError, fn ->
      validate(query)
    end

    query = Post |> select([p], 1 in [123, 123])
    assert_raise Ecto.QueryError, fn ->
      validate(query)
    end

    query = Post |> where([p], array([p.title, p.title], :string) == 1) |> select([], 0)
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end
  end

  test "distinct expression" do
    query = Post |> distinct([p], p.id)
    validate(query)

    query = Post |> distinct([p], p.id * 2)
    validate(query)

    query = Post |> distinct([p], [p.id, p.title])
    validate(query)

    query = Post |> distinct([p], [p.id, p.title]) |> order_by([p], [p.title])
    validate(query)

    query = Post |> distinct([p], [p.id, p.title]) |> order_by([p], [p.title, p.id])
    validate(query)

    query = Post |> select([p], p.title) |> distinct([p], p.title) |> order_by([p], p.title)
    validate(query)

    query = Post |> select([p], p.title) |> distinct([p], p.id) |> order_by([p], [p.id, p.title])
    validate(query)

    query = Post |> select([p], p.title) |> distinct([p], p.id) |> order_by([p], [p.title, p.id])
    assert_raise Ecto.QueryError, ~r"the `order_by` expression should first reference all the `distinct` fields before other fields", fn ->
      validate(query)
    end

    query = Post |> distinct([p], p.title) |> order_by([p], [p.id, p.title])
    assert_raise Ecto.QueryError, ~r"the `order_by` expression should first reference all the `distinct` fields before other fields", fn ->
      validate(query)
    end

    query = Post |> distinct([p], [p.title, p.text]) |> order_by([p], [p.title, p.id])
    assert_raise Ecto.QueryError, ~r"the `order_by` expression should first reference all the `distinct` fields before other fields", fn ->
      validate(query)
    end
  end

  test "group_by invalid field" do
    query = Post |> group_by([p], p.hai) |> select([], 0)
    assert_raise Ecto.QueryError, fn ->
      validate(query)
    end
  end

  test "order_by invalid field" do
    query = Post |> order_by([p], p.hai) |> select([], 0)
    assert_raise Ecto.QueryError, fn ->
      validate(query)
    end
  end

  test "having without group_by" do
    query = Post |> having([], true) |> select([], 0)
    validate(query)

    query = Post |> having([p], p.id) |> select([], 0)
    assert_raise Ecto.QueryError, ~r"`&0.id\(\)` must appear in `group_by`", fn ->
      validate(query)
    end
  end

  test "having with group_by" do
    query = Post |> group_by([p], p.id) |> having([p], p.id == 0) |> select([p], p.id)
    validate(query)

    query = Post |> group_by([p], p.id) |> having([p], p.title) |> select([], 0)
    assert_raise Ecto.QueryError, ~r"`&0.title\(\)` must appear in `group_by`", fn ->
      validate(query)
    end
  end

  test "group_by groups expression" do
    query = Post |> group_by([p], p.id) |> select([p], p.id)
    validate(query)

    query = Post |> group_by([p], p.id * 2) |> select([p], p.id * 2)
    validate(query)

    query = Post |> group_by([p], p.id * 2) |> select([p], p.id)
    assert_raise Ecto.QueryError, ~r"`&0.id\(\)` must appear in `group_by`", fn ->
      validate(query)
    end

    query = Post |> group_by([p], p.id) |> select([p], p.title)
    assert_raise Ecto.QueryError, ~r"`&0.title\(\)` must appear in `group_by`", fn ->
      validate(query)
    end

    query = Post |> group_by([p], p.id) |> order_by([p], p.title)
    assert_raise Ecto.QueryError, ~r"`&0.title\(\)` must appear in `group_by`", fn ->
      validate(query)
    end

    query = Post |> group_by([p], p.id) |> distinct([p], p.title)
    assert_raise Ecto.QueryError, ~r"`&0.title\(\)` must appear in `group_by`", fn ->
      validate(query)
    end
  end

  test "aggregate function groups expression" do
    query = Post |> select([p], [count(p.id), p.title])
    assert_raise Ecto.QueryError, ~r"`&0.title\(\)` must appear in `group_by`", fn ->
      validate(query)
    end

    query = Post |> order_by([p], count(p.id)) |> select([p], p.title)
    assert_raise Ecto.QueryError, ~r"`&0.title\(\)` must appear in `group_by`", fn ->
      validate(query)
    end

    query = Post |> distinct([p], count(p.id)) |> select([p], p.title)
    assert_raise Ecto.QueryError, ~r"`&0.title\(\)` must appear in `group_by`", fn ->
      validate(query)
    end
  end

  test "group_by groups model expression" do
    query = Post |> group_by([p], [p.id, p.title, p.text]) |> select([p], p)
    validate(query)

    query = Post |> group_by([p], p.id) |> select([p], p)
    assert_raise Ecto.QueryError, ~r"`&0.title\(\)` must appear in `group_by`", fn ->
      validate(query)
    end
  end

  test "group_by doesn't group where" do
    query = Post |> group_by([p], p.id) |> where([p], p.title == "") |> select([p], p.id)
    validate(query)
  end

  test "allow functions" do
    query = Post |> select([], avg(0))
    validate(query)
  end

  test "only allow functions in API" do
    query = Post |> select([], forty_two())
    assert_raise Ecto.QueryError, fn ->
      validate(query)
    end

    query = Post |> select([], avg())
    assert_raise Ecto.QueryError, fn ->
      validate(query)
    end
  end

  test "allow grouped fields in aggregate" do
    query = Post |> group_by([p], p.id) |> select([p], avg(p.id))
    validate(query)
  end

  test "allow non-grouped fields in aggregate" do
    query = Post |> group_by([p], p.title) |> select([p], count(p.id))
    validate(query)
  end

  test "don't allow nested aggregates" do
    query = Post |> select([p], count(count(p.id)))
    assert_raise Ecto.QueryError, ~r"aggregate function calls cannot be nested", fn ->
      validate(query)
    end
  end

  test "nils are any type" do
    query = Post |> select([p], 1 == nil)
    validate(query)

    query = Post |> select([p], nil != "abc")
    validate(query)

    query = Post |> select([p], 1 + nil)
    validate(query)

    query = Post |> select([p], array([1, nil, 2], :integer))
    validate(query)

    assert_raise Ecto.Query.TypeCheckError, fn ->
      query = Post |> select([p], "123" + nil)
      validate(query)
    end
  end

  defmodule CustomAPI do
    use Ecto.Query.Typespec

    deft integer
    defs custom(integer) :: integer
  end

  test "multiple query apis" do
    query = Post |> select([p], custom(p.id)) |> Normalizer.normalize
    Validator.validate(query, [CustomAPI])
    Validator.validate(query, [Ecto.Query.API, CustomAPI])
  end

  test "cannot reference virtual field" do
    query = Comment |> select([c], c.temp)
    assert_raise Ecto.QueryError, fn ->
      validate(query)
    end
  end

  test "cannot preload without model" do
    query = "posts" |> preload(:comments)
    assert_raise Ecto.QueryError, fn ->
      validate(query)
    end
  end

  test "can only preload association field" do
    query = Post |> preload(:comments)
    validate(query)

    query = Post |> preload(:title)
    assert_raise Ecto.QueryError, fn ->
      validate(query)
    end
  end

  test "model have to be selected with preload" do
    query = Post |> preload(:comments) |> select([p], p)
    validate(query)

    query = Post |> preload(:comments) |> select([p], 0)
    assert_raise Ecto.QueryError, fn ->
      validate(query)
    end
  end

  test "can preload nested" do
    query = Post |> preload(comments: :post) |> select([p], p)
    validate(query)

    query = Post |> preload(comments: :test) |> select([p], p)
    assert_raise Ecto.QueryError, fn ->
      validate(query)
    end

    query = Post |> preload(comments: :posted) |> select([p], p)
    assert_raise Ecto.QueryError, fn ->
      validate(query)
    end
  end

  test "join have to be followed by on" do
    query = from(c in Comment, join: p in Post, on: true, select: c)
    validate(query)

    query = from(c in "comments", join: p in "posts", on: true, select: c.a)
    validate(query)
  end

  test "assoc selector" do
    query = from(p in Post, join: c in p.comments, select: assoc(p, comments: c))
    validate(query)

    query = from(p in Post, join: c in p.comments, select: assoc(c, post: p))
    validate(query)

    query = from(p in Post, join: c in p.comments, select: assoc(p, not_field: c))
    assert_raise Ecto.QueryError, ~r"field `Ecto.Query.ValidatorTest.Post.not_field` is not an association", fn ->
      validate(query)
    end

    query = from(p in Post, join: c in p.comments, select: assoc(p, permalink: c))
    assert_raise Ecto.QueryError, ~r"doesn't match given model", fn ->
      validate(query)
    end

    query = from(p in Post, join: pl in p.permalink, select: assoc(p, permalink: pl))
    assert_raise Ecto.QueryError, ~r"`assoc/2` selector requires a primary key on", fn ->
      validate(query)
    end

    query = from(p in Post, join: c in Comment, on: true, select: assoc(p, comments: c))
    assert_raise Ecto.QueryError, ~r"can only associate on an inner or left association join", fn ->
      validate(query)
    end
  end

  test "datetime type" do
    datetime = %Ecto.DateTime{year: 2013, month: 8, day: 1, hour: 14, min: 28, sec: 0}
    query = from(c in Comment, where: c.posted == ^datetime, select: c)
    validate(query)

    query = from(c in Comment, where: c.posted == 123, select: c)
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end
  end

  test "date type" do
    date = %Ecto.Date{year: 2013, month: 8, day: 1}
    query = from(c in Comment, where: c.day == ^date, select: c)
    validate(query)

    query = from(c in Comment, where: c.day == 123, select: c)
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end
  end

  test "time type" do
    time = %Ecto.Time{hour: 14, min: 28, sec: 0}
    query = from(c in Comment, where: c.time == ^time, select: c)
    validate(query)

    query = from(c in Comment, where: c.time == 123, select: c)
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end
  end

  test "binary literals" do
    query = from(Post, select: binary("abc") <> binary(<<0,1,2>>))
    validate(query)

    query = from(p in Post, select: binary(p.title))
    validate(query)

    query = from(Post, select: binary("abc") <> "abc")
    assert_raise Ecto.Query.TypeCheckError, fn ->
      validate(query)
    end
  end

  test "source only query" do
    query = from(p in "posts", select: p.any_post)
    validate(query)
  end
end
