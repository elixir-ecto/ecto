Code.require_file "../support/eval_helpers.exs", __DIR__

defmodule Ecto.QueryTest do
  use ExUnit.Case, async: true

  import Support.EvalHelpers
  import Ecto.Query
  alias Ecto.Query

  defmacrop macro_equal(column, value) do
    quote do
      unquote(column) == unquote(value)
    end
  end

  test "query functions do not require binding" do
    _ = from(p in "posts") |> limit(1)
    _ = from(p in "posts") |> order_by([asc: :title])
    _ = from(p in "posts") |> where(title: "foo")
    _ = from(p in "posts") |> having(title: "foo")
    _ = from(p in "posts") |> offset(1)
    _ = from(p in "posts") |> update(set: [title: "foo"])
    _ = from(p in "posts") |> select(1)
    _ = from(p in "posts") |> group_by(1)
    _ = from(p in "posts") |> join(:inner, "comments")
  end

  test "where allows macros" do
    test_data = "test"
    query = from(p in "posts") |> where([q], macro_equal(q.title, ^test_data))
    assert "&0.title() == ^0" == Macro.to_string(hd(query.wheres).expr)
  end

  test "vars are order on_delete" do
    from(p in "posts", []) |> select([q], q.title)
  end

  test "can append to selected query" do
    from(p in "posts", []) |> select([], 1) |> where([], true)
  end

  test "binding should be list of variables" do
    assert_raise Ecto.Query.CompileError,
                 "binding list should contain only variables, got: 0", fn ->
      quote_and_eval select(%Query{}, [0], 1)
    end
  end

  test "does not allow nils in comparison" do
    assert_raise Ecto.Query.CompileError,
                 ~r"comparison with nil is forbidden as it always evaluates to false", fn ->
      quote_and_eval from p in "posts", where: p.id == nil
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
    from(c in "comments", join: p in {"user_posts", Post}, on: c.text == "", select: c)
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

  test "exclude/2 will exclude a passed in field" do
    base = %Ecto.Query{}

    query = from(p in "posts",
                 join: b in "blogs",
                 join: c in "comments",
                 where: p.id == 0 and b.id == 0 and c.id ==0,
                 order_by: p.title,
                 limit: 2,
                 offset: 10,
                 group_by: p.author,
                 having: p.comments > 10,
                 distinct: p.category,
                 lock: "FOO",
                 select: p)

    # Pre-exclusion assertions
    refute query.joins == base.joins
    refute query.wheres == base.wheres
    refute query.order_bys == base.order_bys
    refute query.group_bys == base.group_bys
    refute query.havings == base.havings
    refute query.distinct == base.distinct
    refute query.select == base.select
    refute query.limit == base.limit
    refute query.offset == base.offset
    refute query.lock == base.lock

    excluded_query = query
    |> exclude(:join)
    |> exclude(:where)
    |> exclude(:order_by)
    |> exclude(:group_by)
    |> exclude(:having)
    |> exclude(:distinct)
    |> exclude(:select)
    |> exclude(:limit)
    |> exclude(:offset)
    |> exclude(:lock)

    # Post-exclusion assertions
    assert excluded_query.joins == base.joins
    assert excluded_query.wheres == base.wheres
    assert excluded_query.order_bys == base.order_bys
    assert excluded_query.group_bys == base.group_bys
    assert excluded_query.havings == base.havings
    assert excluded_query.distinct == base.distinct
    assert excluded_query.select == base.select
    assert excluded_query.limit == base.limit
    assert excluded_query.offset == base.offset
    assert excluded_query.lock == base.lock
  end

  test "exclude/2 works with any queryable" do
    query = "posts" |> exclude(:select)
    assert query.from
    refute query.select
  end

  test "exclude/2 will not set a non-existent field to nil" do
    query = from(p in "posts", select: p)
    msg = ~r"no function clause matching in Ecto.Query"

    assert_raise FunctionClauseError, msg, fn ->
      Ecto.Query.exclude(query, :fake_field)
    end
  end

  test "exclude/2 will not reset :from" do
    query = from(p in "posts", select: p)
    msg = ~r"no function clause matching in Ecto.Query"

    assert_raise FunctionClauseError, msg, fn ->
      Ecto.Query.exclude(query, :from)
    end
  end

  test "exclude/2 will reset preloads and assocs if :preloads is passed in" do
    base = %Ecto.Query{}

    query = from p in "posts", join: c in assoc(p, :comments), preload: [:author, comments: c]

    refute query.preloads == base.preloads
    refute query.assocs == base.assocs

    excluded_query = query |> exclude(:preload)

    assert excluded_query.preloads == base.preloads
    assert excluded_query.assocs == base.assocs
  end

  test "fragment/1 raises at runtime when interpolation is not a keyword list" do
    assert_raise ArgumentError, ~r/only a keyword list.*1 = \?/, fn ->
      clause = "1 = ?"
      from p in "posts", where: fragment(^clause)
    end
  end
end
