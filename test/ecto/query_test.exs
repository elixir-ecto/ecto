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

  defmacro macro_map(key) do
    quote do
      %{"1" => unquote(key),
        "2" => unquote(key)}
    end
  end

  describe "query building" do
    test "allows macros" do
      test_data = "test"
      query = from(p in "posts") |> where([q], macro_equal(q.title, ^test_data))
      assert "&0.title() == ^0" == Macro.to_string(hd(query.wheres).expr)
    end

    test "allows macros in select" do
      key = "hello"
      from(p in "posts", select: [macro_map(^key)])
    end

    defmacrop macrotest(x), do: quote(do: is_nil(unquote(x)) or unquote(x) == "A")
    defmacrop deeper_macrotest(x), do: quote(do: macrotest(unquote(x)) or unquote(x) == "B")
    test "allows macro in where" do
      _ = from(p in "posts", where: p.title == "C" or macrotest(p.title))
      _ = from(p in "posts", where: p.title == "C" or deeper_macrotest(p.title))
    end

    test "does not allow nils in comparison at compile time" do
      assert_raise Ecto.Query.CompileError,
                   ~r"comparison with nil is forbidden as it is unsafe", fn ->
        quote_and_eval from p in "posts", where: p.id == nil
      end
    end

    test "does not allow nils in comparison at runtime" do
      assert_raise ArgumentError, ~r"comparison with nil is forbidden as it is unsafe", fn ->
        Post |> where([p], p.title == ^nil)
      end
    end
  end

  describe "from" do
    test "does not allow non-queryable" do
      assert_raise Protocol.UndefinedError, fn ->
        from(p in 123, []) |> select([p], p.title)
      end

      assert_raise UndefinedFunctionError, fn ->
        from(p in NotASchema, []) |> select([p], p.title)
      end
    end

    test "normalizes expressions" do
      quote_and_eval(from("posts", []))

      assert_raise ArgumentError, fn ->
        quote_and_eval(from("posts", [123]))
      end

      assert_raise ArgumentError, fn ->
        quote_and_eval(from("posts", 123))
      end
    end
  end

  describe "subqueries" do
    test "builds a subquery struct" do
      assert subquery("posts").query.from.source == {"posts", nil}
      assert subquery(subquery("posts")).query.from.source == {"posts", nil}
      assert subquery(subquery("posts").query).query.from.source == {"posts", nil}
    end

    test "prefix is not applied if left blank" do
      assert subquery("posts").query.prefix == nil
      assert subquery(subquery("posts")).query.prefix == nil
      assert subquery(subquery("posts").query).query.prefix == nil
    end

    test "applies prefix to the subquery's query if provided" do
      assert subquery("posts", prefix: "my_prefix").query.prefix == "my_prefix"
      assert subquery(subquery("posts", prefix: "my_prefix")).query.prefix == "my_prefix"
      assert subquery(subquery("posts", prefix: "my_prefix").query).query.prefix == "my_prefix"
    end
  end

  describe "bindings" do
    test "are not required by macros" do
      _ = from(p in "posts") |> limit(1)
      _ = from(p in "posts") |> order_by([asc: :title])
      _ = from(p in "posts") |> where(title: "foo")
      _ = from(p in "posts") |> having(title: "foo")
      _ = from(p in "posts") |> offset(1)
      _ = from(p in "posts") |> update(set: [title: "foo"])
      _ = from(p in "posts") |> select([:title])
      _ = from(p in "posts") |> group_by([:title])
      _ = from(p in "posts") |> distinct(true)
      _ = from(p in "posts") |> join(:inner, "comments")
    end

    test "must be a list of variables" do
      assert_raise Ecto.Query.CompileError,
                   "binding list should contain only variables or `{as, var}` tuples, got: 0", fn ->
        quote_and_eval select(%Query{}, [0], 1)
      end
    end

    test "ignore unbound _ var" do
      assert_raise Ecto.Query.CompileError, fn ->
        quote_and_eval("posts" |> select([], _.x))
      end

      "posts" |> select([_], 0)
      "posts" |> join(:inner, [], "comments") |> select([_, c], c.text)
      "posts" |> join(:inner, [], "comments") |> select([p, _], p.title)
      "posts" |> join(:inner, [], "comments") |> select([_, _], 0)
    end

    test "can be added through joins" do
      from(c in "comments", join: p in "posts", select: {p.title, c.text})
      "comments" |> join(:inner, [c], p in "posts", on: true) |> select([c, p], {p.title, c.text})
    end

    test "can be added through joins with a counter" do
      base = join("comments", :inner, [c], p in "posts", on: true)
      assert select(base, [{p, 1}], p) == select(base, [c, p], p)
    end

    test "raise on binding collision" do
      assert_raise Ecto.Query.CompileError, "variable `x` is bound twice", fn ->
        quote_and_eval("posts" |> from("comments") |> select([x, x], x.id))
      end
    end

    test "raise on too many vars" do
      assert from(a in %Query{}, [])
      assert from([] in %Query{}, [])
      assert from([a] in %Query{}, [])

      assert_raise Ecto.Query.CompileError, fn ->
        comment = "comments"
        from([a, b] in comment, [])
      end
    end
  end

  describe "trailing bindings (...)" do
    test "match on last bindings" do
      query = "posts" |> join(:inner, [], "comments") |> join(:inner, [], "votes")
      assert select(query, [..., v], v).select.expr ==
             {:&, [], [2]}

      assert select(query, [p, ..., v], {p, v}).select.expr ==
             {:{}, [], [{:&, [], [0]}, {:&, [], [2]}]}

      assert select(query, [p, c, v, ...], v).select.expr ==
             {:&, [], [2]}

      assert select(query, [..., c, v], {c, v}).select.expr ==
             {:{}, [], [{:&, [], [1]}, {:&, [], [2]}]}
    end

    test "match on last bindings with multiple constructs" do
      query =
        "posts"
        |> join(:inner, [], "comments")
        |> where([..., c], c.public)
        |> join(:inner, [], "votes")
        |> select([..., v], v)

      assert query.select.expr == {:&, [], [2]}
      assert hd(query.wheres).expr == {{:., [], [{:&, [], [1]}, :public]}, [], []}
    end

    test "match on last bindings inside joins" do
      query =
        "posts"
        |> join(:inner, [], "comments")
        |> join(:inner, [..., c], v in "votes", on: c.id == v.id)

      assert hd(tl(query.joins)).on.expr ==
             {:==, [], [
              {{:., [], [{:&, [], [1]}, :id]}, [], []},
              {{:., [], [{:&, [], [2]}, :id]}, [], []}
             ]}
    end

    test "match on last bindings on keyword query" do
      posts = "posts"
      query = from [..., p] in posts, join: c in "comments", on: p.id == c.id
      assert hd(query.joins).on.expr ==
             {:==, [], [
              {{:., [], [{:&, [], [0]}, :id]}, [], []},
              {{:., [], [{:&, [], [1]}, :id]}, [], []}
             ]}
    end

    test "dynamic in :on takes new binding when ... is used" do
      join_on = dynamic([p, ..., c], c.text == "Test Comment")

      query = from p in "posts", join: c in "comments", on: ^join_on

      assert inspect(query) ==
        ~s[#Ecto.Query<from p in \"posts\", join: c in \"comments\", on: c.text == \"Test Comment\">]
    end
  end

  describe "named bindings" do
    test "assigns a name to a join" do
      query =
        from(p in "posts",
          join: b in "blogs",
          join: c in "comments", as: :comment,
          join: l in "links", on: l.valid, as: :link)

      assert %{comment: 2, link: 3} == query.aliases
    end

    test "assigns a name to query source" do
      query = from p in "posts", as: :post

      assert %{post: 0} == query.aliases
      assert %{as: :post} = query.from
    end

    test "assigns a name to query source in var" do
      posts_source = "posts"
      query = from p in posts_source, as: :post

      assert %{post: 0} == query.aliases
      assert %{as: :post} = query.from
    end

    test "assigns a name to a subquery source" do
      posts_query = from p in "posts"
      query = from p in subquery(posts_query), as: :post

      assert %{post: 0} == query.aliases
      assert %{as: :post} = query.from
    end

    test "assign to source fails when non-atom name passed" do
      message = ~r"`as` must be a compile time atom, got: `\"post\"`"
      assert_raise Ecto.Query.CompileError, message, fn ->
        quote_and_eval(from(p in "posts", as: "post"))
      end
    end

    test "crashes on duplicate as for keyword query" do
      message = ~r"`as` keyword was given more than once"
      assert_raise Ecto.Query.CompileError, message, fn ->
        quote_and_eval(from(p in "posts", join: b in "blogs", as: :foo, as: :bar))
      end
    end

    test "crashes on assigning the same name twice at compile time" do
      message = ~r"alias `:foo` already exists"
      assert_raise Ecto.Query.CompileError, message, fn ->
        quote_and_eval(from(p in "posts", join: b in "blogs", as: :foo, join: c in "comments", as: :foo))
      end
    end

    test "crashes on assigning the same name twice at runtime" do
      message = ~r"alias `:foo` already exists"
      assert_raise Ecto.Query.CompileError, message, fn ->
        query = "posts"
        from(p in query, join: b in "blogs", as: :foo, join: c in "comments", as: :foo)
      end
    end

    test "crashes on assigning the same name twice when aliasing source" do
      message = ~r"alias `:foo` already exists"
      assert_raise Ecto.Query.CompileError, message, fn ->
        query = from p in "posts", join: b in "blogs", as: :foo
        from(p in query, as: :foo)
      end
    end

    test "crashes on assigning the name to source when it already has one" do
      message = ~r"can't apply alias `:foo`, binding in `from` is already aliased to `:post`"
      assert_raise Ecto.Query.CompileError, message, fn ->
        query = from p in "posts", as: :post
        from(p in query, as: :foo)
      end
    end

    test "match on binding by name" do
      query =
        "posts"
        |> join(:inner, [p], c in "comments", as: :comment)
        |> where([comment: c], c.id == 0)

      assert inspect(query) ==
        ~s[#Ecto.Query<from p in \"posts\", join: c in \"comments\", as: :comment, on: true, where: c.id == 0>]
    end

    test "match on binding by name for source" do
      query =
        from(p in "posts", as: :post)
        |> where([post: p], p.id == 0)

      assert inspect(query) ==
        ~s[#Ecto.Query<from p in \"posts\", as: :post, where: p.id == 0>]
    end

    test "match on binding by name with ... in the middle" do
      query =
        "posts"
        |> join(:inner, [p], c in "comments")
        |> join(:inner, [], a in "authors", as: :authors)
        |> where([p, ..., authors: a], a.id == 0)

      assert inspect(query) ==
        ~s[#Ecto.Query<from p in \"posts\", join: c in \"comments\", on: true, join: a in \"authors\", as: :authors, on: true, where: a.id == 0>]
    end

    test "referring to non-existing binding" do
      assert_raise Ecto.QueryError, ~r"unknown bind name `:nope`", fn ->
        "posts"
        |> join(:inner, [p], c in "comments", as: :comment)
        |> where([nope: c], c.id == 0)
      end
    end

    test "named bind not in tail of the list" do
      message = ~r"tuples must be at the end of the binding list"
      assert_raise Ecto.Query.CompileError, message, fn ->
      quote_and_eval(
        "posts"
        |> join(:inner, [p], c in "comments", as: :comment)
        |> where([{:comment, c}, p], c.id == 0)
      )
      end
    end

    test "dynamic in :on takes new binding when alias is used" do
      join_on = dynamic([p, comment: c], c.text == "Test Comment")
      query = from p in "posts", join: c in "comments", as: :comment, on: ^join_on

      assert inspect(query) ==
        ~s[#Ecto.Query<from p in \"posts\", join: c in \"comments\", as: :comment, on: c.text == \"Test Comment\">]
    end
  end

  describe "prefixes" do
    test "are supported on from and join" do
      query = from "posts", prefix: "hello", join: "comments", prefix: "world"
      assert query.from.prefix == "hello"
      assert hd(query.joins).prefix == "world"
    end

    test "are supported on dynamic from" do
      posts = "posts"
      query = from posts, prefix: "hello"
      assert query.from.prefix == "hello"
    end

    test "raises when conflicting with dynamic from" do
      posts = from "posts", prefix: "hello"

      message = "can't apply prefix `\"world\"`, `from` is already prefixed to `\"hello\"`"
      assert_raise Ecto.Query.CompileError, message, fn ->
        from posts, prefix: "world"
      end
    end

    test "are expected to be compile-time strings" do
      assert_raise Ecto.Query.CompileError, ~r"`prefix` must be a compile time string", fn ->
        quote_and_eval(from "posts", prefix: 123)
      end

      assert_raise Ecto.Query.CompileError, ~r"`prefix` must be a compile time string", fn ->
        quote_and_eval(from "posts", join: "comments", prefix: 123)
      end
    end
  end

  describe "hints" do
    test "are supported on from and join" do
      query = from "posts", hints: "hello", join: "comments", hints: ["world", "extra"]
      assert query.from.hints == ["hello"]
      assert hd(query.joins).hints == ["world", "extra"]
    end

    test "are supported on dynamic from" do
      posts = "posts"
      query = from posts, hints: "hello"
      assert query.from.hints == ["hello"]

      posts = from "posts", hints: "hello"
      query = from posts, hints: "world"
      assert query.from.hints == ["hello", "world"]
    end

    test "are expected to be compile-time strings or list of strings" do
      assert_raise Ecto.Query.CompileError, ~r"`hints` must be a compile time string", fn ->
        quote_and_eval(from "posts", hints: 123)
      end

      assert_raise Ecto.Query.CompileError, ~r"`hints` must be a compile time string", fn ->
        quote_and_eval(from "posts", join: "comments", hints: 123)
      end
    end
  end

  describe "keyword queries" do
    test "are supported through from/2" do
      # queries need to be on the same line or == wont work
      assert from(p in "posts", select: 1 < 2) == from(p in "posts", []) |> select([p], 1 < 2)
      assert from(p in "posts", where: 1 < 2)  == from(p in "posts", []) |> where([p], 1 < 2)

      query = "posts"
      assert (query |> select([p], p.title)) == from(p in query, select: p.title)
    end

    test "are built at compile time with binaries" do
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

    test "are built at compile time with atoms" do
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

    test "are built at compile time even with joins" do
      from(c in "comments", join: p in "posts", on: c.text == "", select: c)
      from(p in "posts", join: c in assoc(p, :comments), select: p)

      message = ~r"`on` keyword must immediately follow a join"
      assert_raise Ecto.Query.CompileError, message, fn ->
        quote_and_eval(from(c in "comments", on: c.text == "", select: c))
      end
    end
  end

  describe "exclude/2" do
    test "removes the given field" do
      base = %Ecto.Query{}

      query = from(p in "posts",
                   join: b in "blogs",
                   join: c in "comments",
                   where: p.id == 0 and b.id == 0,
                   or_where: c.id == 0,
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

    test "works on any queryable" do
      query = "posts" |> exclude(:select)
      assert query.from
      refute query.select
    end

    test "does not set a non-existent field to nil" do
      query = from(p in "posts", select: p)
      msg = ~r"no function clause matching in Ecto.Query"

      assert_raise FunctionClauseError, msg, fn ->
        Ecto.Query.exclude(query, :fake_field)
      end
    end

    test "does not reset :from" do
      query = from(p in "posts", select: p)
      msg = ~r"no function clause matching in Ecto.Query"

      assert_raise FunctionClauseError, msg, fn ->
        Ecto.Query.exclude(query, :from)
      end
    end

    test "resets both preloads and assocs if :preloads is passed in" do
      base = %Ecto.Query{}

      query = from p in "posts", join: c in assoc(p, :comments), preload: [:author, comments: c]

      refute query.preloads == base.preloads
      refute query.assocs == base.assocs

      excluded_query = query |> exclude(:preload)

      assert excluded_query.preloads == base.preloads
      assert excluded_query.assocs == base.assocs
    end

    test "removes join qualifiers" do
      base = %Ecto.Query{}

      inner_query         = from p in "posts", inner_join: b in "blogs"
      cross_query         = from p in "posts", cross_join: b in "blogs"
      left_query          = from p in "posts", left_join: b in "blogs"
      right_query         = from p in "posts", right_join: b in "blogs"
      full_query          = from p in "posts", full_join: b in "blogs"
      inner_lateral_query = from p in "posts", inner_lateral_join: b in "blogs"
      left_lateral_query  = from p in "posts", left_lateral_join: b in "blogs"

      refute inner_query.joins == base.joins
      refute cross_query.joins == base.joins
      refute left_query.joins == base.joins
      refute right_query.joins == base.joins
      refute full_query.joins == base.joins
      refute inner_lateral_query.joins == base.joins
      refute left_lateral_query.joins == base.joins

      excluded_inner_query = exclude(inner_query, :inner_join)
      assert excluded_inner_query.joins == base.joins

      excluded_cross_query = exclude(cross_query, :cross_join)
      assert excluded_cross_query.joins == base.joins

      excluded_left_query = exclude(left_query, :left_join)
      assert excluded_left_query.joins == base.joins

      excluded_right_query = exclude(right_query, :right_join)
      assert excluded_right_query.joins == base.joins

      excluded_full_query = exclude(full_query, :full_join)
      assert excluded_full_query.joins == base.joins

      excluded_inner_lateral_query = exclude(inner_lateral_query, :inner_lateral_join)
      assert excluded_inner_lateral_query.joins == base.joins

      excluded_left_lateral_query = exclude(left_lateral_query, :left_lateral_join)
      assert excluded_left_lateral_query.joins == base.joins
    end
  end

  describe "fragment/1" do
    test "raises at runtime when interpolation is not a keyword list" do
      assert_raise ArgumentError, ~r/fragment\(...\) allows only keyword lists/s, fn ->
        clause = ["1 = ?"]
        from p in "posts", where: fragment(^clause)
      end
    end

    test "raises at runtime when interpolation is a binary string" do
      assert_raise ArgumentError, ~r/fragment\(...\) allows only keyword lists/, fn ->
        clause = "1 = ?"
        from p in "posts", where: fragment(^clause)
      end
    end

    test "keeps UTF-8 encoding" do
      assert inspect(from p in "posts", where: fragment("héllò")) ==
             ~s[#Ecto.Query<from p in \"posts\", where: fragment("héllò")>]
    end
  end

  describe "unsafe_fragment/1" do
    test "raises with non interpolated binary fragment" do
      message = ~r"unsafe_fragment\(...\) expects the first argument"
      assert_raise Ecto.Query.CompileError, message, fn ->
        quote_and_eval(
          from p in "posts", where: unsafe_fragment("1 = 1")
        )
      end
    end

    test "raises at runtime when interpolation is not a string" do
      assert_raise ArgumentError, ~r"unsafe_fragment\(...\) expects the first argument", fn ->
        clause = [foo: "bar"]
        from p in "posts", where: unsafe_fragment(^clause)
      end
    end

    test "raises at runtime on parameter mismatch" do
      assert_raise ArgumentError, ~r"unsafe_fragment\(...\) expects extra arguments", fn ->
        from p in "posts", where: unsafe_fragment(^"foo = bar", 1)
      end
    end

    test "works with interpolated binary fragment" do
      val = 1
      clause = "1 = #{val}"
      query = from p in "posts", where: unsafe_fragment(^clause)

      assert inspect(query) ==
            ~s[#Ecto.Query<from p in \"posts\", where: fragment(\"1 = 1\")>]
    end

    test "works with interpolated binary fragment and question marks" do
      clause = "? = ?"
      query = from p in "posts", where: unsafe_fragment(^clause, 1, 2)

      assert inspect(query) ==
            ~s[#Ecto.Query<from p in \"posts\", where: fragment(\"? = ?\", 1, 2)>]
    end

    test "keeps UTF-8 encoding" do
      clause = "héllò"
      assert inspect(from p in "posts", where: unsafe_fragment(^clause)) ==
             ~s[#Ecto.Query<from p in \"posts\", where: fragment("héllò")>]
    end
  end
end
