Code.require_file "../support/eval_helpers.exs", __DIR__

defmodule Ecto.QueryTest do
  use ExUnit.Case, async: true

  import Support.EvalHelpers
  import Ecto.Query
  alias Ecto.Query

  test "vars are order dependent" do
    from(p in "posts", []) |> select([q], q.title)
  end

  test "can append to selected query" do
    from(p in "posts", []) |> select([], 1) |> where([], true)
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
    quote_and_eval(from("posts", []))

    assert_raise ArgumentError, fn ->
      quote_and_eval(from("posts", [123]))
    end

    assert_raise ArgumentError, fn ->
      quote_and_eval(from("posts", 123))
    end
  end

  test "unbound _ var" do
    assert_raise Ecto.Query.CompileError, fn ->
      quote_and_eval("posts" |> select([], _.x))
    end

    "posts" |> select([_], 0)
    "posts" |> join(:inner, [], "comments") |> select([_, c], c.text)
    "posts" |> join(:inner, [], "comments") |> select([p, _], p.title)
    "posts" |> join(:inner, [], "comments") |> select([_, _], 0)
  end

  test "binding collision" do
    assert_raise Ecto.Query.CompileError, "variable `x` is bound twice", fn ->
      quote_and_eval("posts" |> from("comments") |> select([x, x], x.id))
    end
  end

  test "cannot bind too many vars" do
    from(a in %Query{}, [])
    from([a] in %Query{}, [])

    assert_raise Ecto.Query.CompileError, fn ->
      comment = "comments"
      from([a, b] in comment, [])
    end
  end

  test "keyword query" do
    # queries need to be on the same line or == wont work
    assert from(p in "posts", select: 1<2) == from(p in "posts", []) |> select([p], 1<2)
    assert from(p in "posts", where: 1<2)  == from(p in "posts", []) |> where([p], 1<2)

    query = "posts"
    assert (query |> select([p], p.title)) == from(p in query, select: p.title)
  end

  test "keyword query builder is compile time with binaries" do
    quoted =
      quote do
        from(p in "posts",
             join: b in "blogs",
             join: c in "comments", on: c.text == "",
             limit: 0,
             where: p.id == 0 and b.id == 0 and c.id == 0,
             select: p)
      end

    assert {:%{}, _, list} = Macro.expand(quoted, __ENV__)
    assert List.keyfind(list, :__struct__, 0) == {:__struct__, Query}
  end

  test "keyword query builder is compile time and lazy with atoms" do
    quoted =
      quote do
        from(p in Post,
             join: b in Blog,
             join: c in Comment, on: c.text == "",
             limit: 0,
             where: p.id == 0 and b.id == 0 and c.id == 0,
             select: p)
      end

    assert {:%{}, _, list} = Macro.expand(quoted, __ENV__)
    assert List.keyfind(list, :__struct__, 0) == {:__struct__, Query}
  end

  test "join on keyword query" do
    from(c in "comments", join: p in "posts", on: c.text == "", select: c)
    from(p in "posts", join: c in assoc(p, :comments), select: p)

    message = ~r"`on` keyword must immediately follow a join"
    assert_raise Ecto.Query.CompileError, message, fn ->
      quote_and_eval(from(c in "comments", on: c.text == "", select: c))
    end

    message = ~r"cannot specify `on` on `inner_join` when using association join,"
    assert_raise Ecto.Query.CompileError, message, fn ->
      quote_and_eval(from(c in "comments", join: p in assoc(c, :post), on: true))
    end
  end

  test "join queries adds binds" do
    from(c in "comments", join: p in "posts", select: {p.title, c.text})
    "comments" |> join(:inner, [c], p in "posts", true) |> select([c,p], {p.title, c.text})
  end

  test "join queries adds binds with custom values" do
    base = join("comments", :inner, [c], p in "posts", true)
    assert select(base, [p: 1], p) == select(base, [c, p], p)
  end
end
