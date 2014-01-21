defmodule Ecto.QueryTest do
  use ExUnit.Case, async: true

  import Support.CompileHelpers
  import Ecto.Query

  alias Ecto.Query.Query
  alias Ecto.Query.Normalizer
  alias Ecto.Query.Validator

  defmodule Post do
    use Ecto.Model

    queryable :posts do
      field :title, :string
      has_many :comments, Ecto.QueryTest.Comment
    end
  end

  defmodule Comment do
    use Ecto.Model

    queryable :comments do
      field :text, :string
    end
  end

  def validate(query) do
    query
    |> Normalizer.normalize
    |> Validator.validate([Ecto.Query.API])
  end

  test "call queryable on every merge" do
    query = Post |> select([p], p.title)
    validate(query)

    query = Post |> distinct([p], p.title)
    validate(query)

    query = Post |> where([p], p.title == "42")
    validate(query)

    query = Post |> order_by([p], p.title)
    validate(query)

    query = Post |> limit(42)
    validate(query)

    query = Post |> offset(43)
    validate(query)

    query = select(Post, [p], p.title)
    validate(query)

    query = distinct(Post, [p], p.title)
    validate(query)
    
    query = where(Post, [p], p.title == "42")
    validate(query)

    query = order_by(Post, [p], p.title)
    validate(query)

    query = limit(Post, 42)
    validate(query)

    query = offset(Post, 43)
    validate(query)
  end

  test "vars are order dependent" do
    query = from(p in Post, []) |> select([q], q.title)
    validate(query)
  end

  test "can append to selected query" do
    query = from(p in Post, []) |> select([], 1) |> where([], true)
    validate(query)
  end

  test "only one select is allowed" do
    assert_raise Ecto.QueryError, "only one select expression is allowed in query", fn ->
      post = Post
      post |> select([], 1) |> select([], 2)
    end
  end

  test "binding should be list of variables" do
    assert_raise Ecto.QueryError, "binding list should contain only variables, got: 0", fn ->
      delay_compile select(Query[], [0], 1)
    end
  end

  test "keyword query" do
    # queries need to be on the same line or == wont work
    assert from(p in Post, select: 1+2) == from(p in Post, []) |> select([p], 1+2)

    assert from(p in Post, where: 1<2) == from(p in Post, []) |> where([p], 1<2)

    query = Post
    assert (query |> select([p], p.title)) == from(p in query, select: p.title)
  end

  test "cannot bind non-Queryable in from" do
    assert_raise Protocol.UndefinedError, fn ->
      from(p in 123, []) |> select([p], p.title)
    end

    assert_raise Protocol.UndefinedError, fn ->
      from(p in NotAnEntity, []) |> select([p], p.title)
    end
  end

  test "string source query" do
    assert Query[from: { "posts", nil, nil }] = from(p in "posts", []) |> select([p], p.title)
  end

  test "validate from expression" do
    delay_compile(from(Post, []))

    assert_raise ArgumentError, fn ->
      delay_compile(from(Post, [123]))
    end

    assert_raise ArgumentError, fn ->
      delay_compile(from(Post, 123))
    end
  end

  test "unbound _ var" do
    assert_raise Ecto.QueryError, fn ->
      delay_compile(Post |> select([], _.x))
    end

    query = Post |> select([_], 0)
    validate(query)

    query = Post |> join(:inner, [], Comment, true) |> select([_, c], c.text)
    validate(query)

    query = Post |> join(:inner, [], Comment, true) |> select([p, _], p.title)
    validate(query)

    query = Post |> join(:inner, [], Comment, true) |> select([_, _], 0)
    validate(query)
  end

  test "binding collision" do
    assert_raise Ecto.QueryError, "variable `x` is bound twice", fn ->
      delay_compile(Post |> from(Comment) |> select([x, x], x.id))
    end
  end

  test "join on keyword query" do
    from(c in Comment, join: p in Post, on: c.text == "", select: c)
    from(p in Post, join: c in p.comments, on: c.text == "", select: p)

    assert_raise Ecto.QueryError, "`on` keyword must immediatelly follow a join", fn ->
      delay_compile(from(c in Comment, on: c.text == "", select: c))
    end

    message = "`join` expression requires explicit `on` " <>
              "expression unless association join expression"
    assert_raise Ecto.QueryError, message, fn ->
      delay_compile(from(c in Comment, join: p in Post, select: c))
    end
  end

  test "join queries adds binds" do
    from(c in Comment, join: p in Post, on: true, select: { p.title, c.text })
    Comment |> join(:inner, [c], p in Post, true) |> select([c,p], { p.title, c.text })
  end

  test "cannot bind too many vars" do
    from(a in Query[], [])
    from([a] in Query[], [])

    assert_raise Ecto.QueryError, fn ->
      comment = Comment
      from([a, b] in comment, [])
    end
  end
end
