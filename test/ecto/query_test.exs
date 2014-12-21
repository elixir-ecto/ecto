defmodule Ecto.QueryTest do
  use ExUnit.Case, async: true

  import Support.EvalHelpers
  import Ecto.Query

  alias Ecto.Query
  alias Ecto.Query.Planner

  defmodule Post do
    use Ecto.Model

    schema "posts" do
      field :title, :string
      has_many :comments, Ecto.QueryTest.Comment
    end
  end

  defmodule Comment do
    use Ecto.Model

    schema "comments" do
      field :text, :string
    end
  end

  def normalize(query) do
    {query, params} = Planner.prepare(query, %{})
    {Planner.normalize(query, %{}, []), params}
  end

  test "is queryable on every merge" do
    query = Post |> select([p], p.title)
    normalize(query)

    query = Post |> distinct([p], p.title)
    normalize(query)

    query = Post |> where([p], p.title == "42")
    normalize(query)

    query = Post |> order_by([p], p.title)
    normalize(query)

    query = Post |> limit([p], 42)
    normalize(query)

    query = Post |> offset([p], 43)
    normalize(query)

    query = Post |> lock(true)
    normalize(query)

    query = Post |> lock("FOR SHARE NOWAIT")
    normalize(query)

    query = select(Post, [p], p.title)
    normalize(query)

    query = distinct(Post, [p], p.title)
    normalize(query)

    query = where(Post, [p], p.title == "42")
    normalize(query)

    query = order_by(Post, [p], p.title)
    normalize(query)

    query = limit(Post, [p], 42)
    normalize(query)

    query = offset(Post, [p], 43)
    normalize(query)

    query = preload(Post, :comments)
    normalize(query)
  end

  test "is queryable with runtime values" do
    comments = :comments
    query = preload(Post, comments)
    normalize(query)

    lock = true
    query = lock(Post, lock)
    normalize(query)

    asc = :asc
    query = order_by(Post, [p], [{^asc, p.title}])
    normalize(query)
  end

  test "vars are order dependent" do
    query = from(p in Post, []) |> select([q], q.title)
    normalize(query)
  end

  test "can append to selected query" do
    query = from(p in Post, []) |> select([], 1) |> where([], true)
    normalize(query)
  end

  test "binding should be list of variables" do
    assert_raise Ecto.Query.CompileError, "binding list should contain only variables, got: 0", fn ->
      quote_and_eval select(%Query{}, [0], 1)
    end
  end

  test "cannot bind non-Queryable in from" do
    assert_raise Protocol.UndefinedError, fn ->
      from(p in 123, []) |> select([p], p.title)
    end

    assert_raise UndefinedFunctionError, fn ->
      from(p in NotAModel, []) |> select([p], p.title)
    end
  end

  test "string source query" do
    assert %Query{from: {"posts", nil}} = from(p in "posts", []) |> select([p], p.title)
  end

  test "normalize from expression" do
    quote_and_eval(from(Post, []))

    assert_raise ArgumentError, fn ->
      quote_and_eval(from(Post, [123]))
    end

    assert_raise ArgumentError, fn ->
      quote_and_eval(from(Post, 123))
    end
  end

  test "unbound _ var" do
    assert_raise Ecto.Query.CompileError, fn ->
      quote_and_eval(Post |> select([], _.x))
    end

    query = Post |> select([_], 0)
    normalize(query)

    query = Post |> join(:inner, [], Comment, true) |> select([_, c], c.text)
    normalize(query)

    query = Post |> join(:inner, [], Comment, true) |> select([p, _], p.title)
    normalize(query)

    query = Post |> join(:inner, [], Comment, true) |> select([_, _], 0)
    normalize(query)
  end

  test "binding collision" do
    assert_raise Ecto.Query.CompileError, "variable `x` is bound twice", fn ->
      quote_and_eval(Post |> from(Comment) |> select([x, x], x.id))
    end
  end

  test "cannot bind too many vars" do
    from(a in %Query{}, [])
    from([a] in %Query{}, [])

    assert_raise Ecto.Query.CompileError, fn ->
      comment = Comment
      from([a, b] in comment, [])
    end
  end

  test "keyword query" do
    # queries need to be on the same line or == wont work
    assert from(p in Post, select: 1<2) == from(p in Post, []) |> select([p], 1<2)
    assert from(p in Post, where: 1<2)  == from(p in Post, []) |> where([p], 1<2)

    query = Post
    assert (query |> select([p], p.title)) == from(p in query, select: p.title)
  end

  test "keyword query builder is compile time" do
    quoted =
      quote do
        from(p in Post,
             join: c in p.comments,
             join: cc in Comment, on: c.text == "",
             limit: 0,
             where: p.id == 0 and c.id == 0 and cc.id == 0,
             select: p)
      end

    assert {:%{}, _, list} = Macro.expand(quoted, __ENV__)
    assert List.keyfind(list, :__struct__, 0) == {:__struct__, Query}
  end

  test "join on keyword query" do
    from(c in Comment, join: p in Post, on: c.text == "", select: c)
    from(p in Post, join: c in p.comments, on: c.text == "", select: p)

    assert_raise Ecto.Query.CompileError, "`on` keyword must immediately follow a join", fn ->
      quote_and_eval(from(c in Comment, on: c.text == "", select: c))
    end
  end

  test "join queries adds binds" do
    from(c in Comment, join: p in Post, select: {p.title, c.text})
    Comment |> join(:inner, [c], p in Post, true) |> select([c,p], {p.title, c.text})
  end
end
