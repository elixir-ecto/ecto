defmodule Ecto.QueryTest do
  use ExUnit.Case, async: true

  import Support.CompileHelpers
  import Ecto.Query

  alias Ecto.Query.Query
  alias Ecto.Query.Util

  defmodule Post do
    use Ecto.Model

    queryable :posts do
      field :title, :string
    end
  end

  defmodule Comment do
    use Ecto.Model

    queryable :comments do
      field :text, :string
    end
  end

  def validate(query), do: query |> Util.normalize |> Util.validate([Ecto.Query.API])

  test "call queryable on every merge" do
    query = from(Post) |> select([p], p.title)
    validate(query)

    query = from(Post) |> where([p], p.title == "42")
    validate(query)

    query = from(Post) |> order_by([p], p.title)
    validate(query)

    query = from(Post) |> limit(42)
    validate(query)

    query = from(Post) |> offset(43)
    validate(query)

    query = select(Post, [p], p.title)
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
    query = from(p in Post) |> select([q], q.title)
    validate(query)
  end

  test "can append to selected query" do
    query = from(p in Post) |> select([], 1) |> where([], true)
    validate(query)
  end

  test "only one select is allowed" do
    assert_raise Ecto.QueryError, "only one select expression is allowed in query", fn ->
      post = Post
      from(p in post) |> select([], 1) |> select([], 2)
    end
  end

  test "binding should be list of variables" do
    assert_raise Ecto.QueryError, "binding list should contain only variables, got: 0", fn ->
      delay_compile select(Query[], [0], 1)
    end
  end

  test "keyword query" do
    # queries need to be on the same line or == wont work
    assert from(p in Post, []) == from(p in Post)

    assert from(p in Post, select: 1+2) == from(p in Post) |> select([p], 1+2)

    assert from(p in Post, where: 1<2) == from(p in Post) |> where([p], 1<2)
  end

  test "variable is already defined" do
    assert_raise Ecto.QueryError, "variable `p` is already defined in query", fn ->
      delay_compile(from(p in Post, from: p in Post))
    end
  end

  test "extend keyword query" do
    query = from(p in Post)
    assert (query |> select([p], p.title)) == from(p in query, select: p.title)

    query = from(p in Post)
    assert (query |> select([p], p.title)) == from([p] in query, select: p.title)

    query = Post
    assert (query |> select([p], p.title)) == from([p] in query, select: p.title)
  end

  test "cannot bind non-Queryable in from" do
    assert_raise Protocol.UndefinedError, fn ->
      from(p in 123) |> select([p], p.title)
    end

    assert_raise Protocol.UndefinedError, fn ->
      from(p in NotAnEntity) |> select([p], p.title)
    end
  end

  test "string source query" do
    assert Query[from: { "posts", nil, nil }] = from(p in "posts") |> select([p], p.title)
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
      delay_compile(from(Post) |> select([], _.x))
    end

    query = from(Post) |> select([_], 0)
    validate(query)

    query = from(Post) |> join(:inner, [], Comment, true) |> select([_, c], c.text)
    validate(query)

    query = from(Post) |> join(:inner, [], Comment, true) |> select([p, _], p.title)
    validate(query)

    query = from(Post) |> join(:inner, [], Comment, true) |> select([_, _], 0)
    validate(query)
  end

  test "binding collision" do
    assert_raise Ecto.QueryError, "variable `x` is bound twice", fn ->
      delay_compile(from(Post) |> from(Comment) |> select([x, x], x.id))
    end

    assert_raise Ecto.QueryError, "variable `x` is already defined in query", fn ->
      delay_compile(from(x in Post, from: x in Comment, select: x.id))
    end
  end

  test "join on keyword query" do
    from(c in Comment, join: p in Post, on: c.text == "", select: c)

    assert_raise Ecto.QueryError, "an `on` query expression must follow a `join`", fn ->
      delay_compile(from(c in Comment, on: c.text == "", select: c))
    end
  end

  test "join queries adds binds" do
    from(c in Comment, join: p in Post, on: true, select: { p.title, c.text })
    from(Comment) |> join(:inner, [c], p in Post, true) |> select([c,p], { p.title, c.text })
  end

  test "cannot bind too many vars" do
    from(a in Query[])
    from([a] in Query[])

    assert_raise Ecto.QueryError, fn ->
      comment = Comment
      from([a, b] in comment)
    end
  end
end
