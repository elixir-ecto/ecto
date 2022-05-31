Code.require_file "../support/eval_helpers.exs", __DIR__

defmodule Ecto.QueryTest.Macros do
  defmacro macro_equal(column, value) do
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

  defmacro macrotest(x), do: quote(do: is_nil(unquote(x)) or unquote(x) == "A")
  defmacro deeper_macrotest(x), do: quote(do: macrotest(unquote(x)) or unquote(x) == "B")
end

defmodule Ecto.QueryTest do
  use ExUnit.Case, async: true

  import Support.EvalHelpers
  import Ecto.Query
  import Ecto.QueryTest.Macros
  require Ecto.QueryTest.Macros, as: Macros
  alias Ecto.Query

  defmodule Schema do
    use Ecto.Schema
    schema "schema" do
    end
  end

  describe "query building" do
    test "allows macros" do
      test_data = "test"
      query = from(p in "posts") |> where([q], Macros.macro_equal(q.title, ^test_data))
      assert "&0.title() == ^0" == Macro.to_string(hd(query.wheres).expr)
      query = from(p in "posts") |> where([q], macro_equal(q.title, ^test_data))
      assert "&0.title() == ^0" == Macro.to_string(hd(query.wheres).expr)
    end

    test "allows macros in select" do
      key = "hello"
      from(p in "posts", select: [macro_map(^key)])
    end

    test "allows macro in where" do
      _ = from(p in "posts", where: p.title == "C" or Macros.macrotest(p.title))
      _ = from(p in "posts", where: p.title == "C" or macrotest(p.title))
      _ = from(p in "posts", where: p.title == "C" or Macros.deeper_macrotest(p.title))
      _ = from(p in "posts", where: p.title == "C" or deeper_macrotest(p.title))
    end

    test "does not allow nils in comparison at compile time" do
      assert_raise Ecto.Query.CompileError,
                   ~r"comparison with nil is forbidden as it is unsafe", fn ->
        quote_and_eval from p in "posts", where: p.id == nil
      end
    end

    test "does not allow interpolated nils at runtime" do
      assert_raise ArgumentError,
                   ~r"comparison with nil is forbidden as it is unsafe", fn ->
        id = nil
        from p in "posts", where: [id: ^id]
      end
    end

    test "allows arbitrary parentheses in where" do
      _ = from(p in "posts", where: (not is_nil(p.title)))
    end
  end

  describe "from" do
    @compile {:no_warn_undefined, NotASchema}

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
      assert subquery("posts", prefix: nil).query.prefix == nil
      assert subquery("posts", prefix: "my_prefix").query.prefix == "my_prefix"
      assert subquery(subquery("posts", prefix: "my_prefix")).query.prefix == "my_prefix"
      assert subquery(subquery("posts", prefix: "my_prefix").query).query.prefix == "my_prefix"
    end
  end

  describe "combinations" do
    test "adds union expressions" do
      union_query1 = from(p in "posts1")
      union_query2 = from(p in "posts2")

      query =
        "posts"
        |> union(^union_query1)
        |> union_all(^union_query2)

      assert {:union, ^union_query1} = query.combinations |> Enum.at(0)
      assert {:union_all, ^union_query2} = query.combinations |> Enum.at(1)
    end

    test "adds except expressions" do
      except_query1 = from(p in "posts1")
      except_query2 = from(p in "posts2")

      query =
        "posts"
        |> except(^except_query1)
        |> except_all(^except_query2)

      assert {:except, ^except_query1} = query.combinations |> Enum.at(0)
      assert {:except_all, ^except_query2} = query.combinations |> Enum.at(1)
    end

    test "adds intersect expressions" do
      intersect_query1 = from(p in "posts1")
      intersect_query2 = from(p in "posts2")

      query =
        "posts"
        |> intersect(^intersect_query1)
        |> intersect_all(^intersect_query2)

      assert {:intersect, ^intersect_query1} = query.combinations |> Enum.at(0)
      assert {:intersect_all, ^intersect_query2} = query.combinations |> Enum.at(1)
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

  describe "put_query_prefix" do
    test "stores prefix in query" do
      assert put_query_prefix(from("posts"), "hello").prefix == "hello"
      assert put_query_prefix(Schema, "hello").prefix == "hello"
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
        ~s[#Ecto.Query<from p0 in \"posts\", join: c1 in \"comments\", on: c1.text == \"Test Comment\">]
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
      message = ~r/`as` must be a compile time atom or an interpolated value using \^, got: "post"/
      assert_raise Ecto.Query.CompileError, message, fn -> 
        quote_and_eval(from(p in "posts", as: "post"))
      end
    end

    test "is not type checked but emits typed params" do
      query = from "addresses", as: :address
      query = where(query, [address: q], field(q, ^:foo) == ago(^1, "year"))
      assert hd(query.wheres).params != []
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
        ~s[#Ecto.Query<from p0 in \"posts\", join: c1 in \"comments\", as: :comment, on: true, where: c1.id == 0>]
    end

    test "match on binding by name for source" do
      query =
        from(p in "posts", as: :post)
        |> where([post: p], p.id == 0)

      assert inspect(query) ==
        ~s[#Ecto.Query<from p0 in \"posts\", as: :post, where: p0.id == 0>]
    end

    test "match on binding by name for source and join" do
      query =
        "posts"
        |> from(as: :post)
        |> join(:inner, [post: p], c in "comments", as: :comment, on: p.id == c.post_id)
        |> update([comment: c], set: [id: c.id + 1])

      assert inspect(query) ==
        ~s{#Ecto.Query<from p0 in "posts", as: :post, join: c1 in "comments", as: :comment, on: p0.id == c1.post_id, update: [set: [id: c1.id + 1]]>}
    end

    test "match on binding by name with ... in the middle" do
      query =
        "posts"
        |> join(:inner, [p], c in "comments")
        |> join(:inner, [], a in "authors", as: :authors)
        |> where([p, ..., authors: a], a.id == 0)

      assert inspect(query) ==
        ~s[#Ecto.Query<from p0 in \"posts\", join: c1 in \"comments\", on: true, join: a2 in \"authors\", as: :authors, on: true, where: a2.id == 0>]
    end

    test "crashes on non-existing binding" do
      assert_raise Ecto.QueryError, ~r"unknown bind name `:nope`", fn ->
        "posts"
        |> join(:inner, [p], c in "comments", as: :comment)
        |> where([nope: c], c.id == 0)
      end
    end

    test "crashes on bind not in tail of the list" do
      message = ~r"tuples must be at the end of the binding list"
      assert_raise Ecto.Query.CompileError, message, fn ->
      quote_and_eval(
        "posts"
        |> join(:inner, [p], c in "comments", as: :comment)
        |> where([{:comment, c}, p], c.id == 0)
      )
      end
    end

    test "dynamic bind" do
      assoc = :comment

      query =
        "posts"
        |> join(:inner, [p], c in "comments", as: :comment)
        |> where([{^assoc, c}], c.id == 0)

      assert inspect(query) ==
        ~s[#Ecto.Query<from p0 in \"posts\", join: c1 in \"comments\", as: :comment, on: true, where: c1.id == 0>]
    end

    test "dynamic in :on takes new binding when alias is used" do
      join_on = dynamic([p, comment: c], c.text == "Test Comment")
      query = from p in "posts", join: c in "comments", as: :comment, on: ^join_on

      assert inspect(query) ==
        ~s[#Ecto.Query<from p0 in \"posts\", join: c1 in \"comments\", as: :comment, on: c1.text == \"Test Comment\">]
    end
  end

  describe "prefixes" do
    defmodule Post do
      use Ecto.Schema
      @schema_prefix "another"
      schema "posts" do
      end
    end

    test "are supported on from and join" do
      query = from "posts", prefix: "hello", join: "comments", prefix: "world"
      assert query.from.prefix == "hello"
      assert hd(query.joins).prefix == "world"
    end

    test "are supported and overridden from schemas" do
      query = from(Post)
      assert query.from.prefix == "another"

      query = from(Post, prefix: "hello")
      assert query.from.prefix == "hello"

      query = from(Post, prefix: nil)
      assert query.from.prefix == nil
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

    test "binary values are expected to be compile-time strings or list of strings" do
      assert_raise Ecto.Query.CompileError, ~r"`hints` must be a compile time string", fn ->
        quote_and_eval(from "posts", hints: 123)
      end

      assert_raise Ecto.Query.CompileError, ~r"`hints` must be a compile time string", fn ->
        quote_and_eval(from "posts", join: "comments", hints: 123)
      end
    end

    test "tuple values are not checked for contents" do
      hint = "hint_from_config"
      query = from "posts", hints: [dynamic: hint, number: 123]
      assert query.from.hints == [dynamic: hint, number: 123]
    end
  end

  describe "keyword queries" do
    test "are supported through from/2" do
      # queries need to be on the same line or == won't work
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

      query =
        from(p in "posts",
          join: b in "blogs",
          join: c in "comments",
          where: p.id == 0 and b.id == 0,
          or_where: c.id == 0,
          order_by: p.title,
          union: ^from(p in "posts"),
          union_all: ^from(p in "posts"),
          except: ^from(p in "posts"),
          intersect: ^from(p in "posts"),
          limit: 2,
          offset: 10,
          group_by: p.author,
          having: p.comments > 10,
          distinct: p.category,
          lock: "FOO",
          select: p
        )

      query = query |> with_cte("cte", as: ^from(p in "posts"))

      # Pre-exclusion assertions
      refute query.with_ctes == base.with_ctes
      refute query.joins == base.joins
      refute query.wheres == base.wheres
      refute query.order_bys == base.order_bys
      refute query.group_bys == base.group_bys
      refute query.havings == base.havings
      refute query.distinct == base.distinct
      refute query.select == base.select
      refute query.combinations == base.combinations
      refute query.limit == base.limit
      refute query.offset == base.offset
      refute query.lock == base.lock

      excluded_query =
        query
        |> exclude(:with_ctes)
        |> exclude(:join)
        |> exclude(:where)
        |> exclude(:order_by)
        |> exclude(:group_by)
        |> exclude(:having)
        |> exclude(:distinct)
        |> exclude(:select)
        |> exclude(:combinations)
        |> exclude(:limit)
        |> exclude(:offset)
        |> exclude(:lock)

      # Post-exclusion assertions
      assert excluded_query.with_ctes == base.with_ctes
      assert excluded_query.joins == base.joins
      assert excluded_query.wheres == base.wheres
      assert excluded_query.order_bys == base.order_bys
      assert excluded_query.group_bys == base.group_bys
      assert excluded_query.havings == base.havings
      assert excluded_query.distinct == base.distinct
      assert excluded_query.select == base.select
      assert excluded_query.combinations == base.combinations
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

    test "removes join qualifiers with named bindings" do
      query =
        from p in "posts", as: :base,
          inner_join: bi in "blogs",
          as: :blogs_i,
          cross_join: bc in "blogs",
          as: :blogs_c,
          left_join: bl in "blogs",
          as: :blogs_l,
          right_join: br in "blogs",
          as: :blogs_r,
          full_join: bf in "blogs",
          as: :blogs_f,
          inner_lateral_join: bil in "blogs",
          as: :blogs_il,
          left_lateral_join: bll in "blogs",
          as: :blogs_ll

      original_joins_number = length(query.joins)
      original_aliases_number = map_size(query.aliases)

      excluded_inner_join_query = exclude(query, :inner_join)
      assert length(excluded_inner_join_query.joins) == original_joins_number - 1
      assert map_size(excluded_inner_join_query.aliases) == original_aliases_number - 1
      refute Map.has_key?(excluded_inner_join_query.aliases, :blogs_i)
      assert Map.has_key?(excluded_inner_join_query.aliases, :base)

      excluded_cross_join_query = exclude(query, :cross_join)
      assert length(excluded_cross_join_query.joins) == original_joins_number - 1
      assert map_size(excluded_cross_join_query.aliases) == original_aliases_number - 1
      refute Map.has_key?(excluded_cross_join_query.aliases, :blogs_c)
      assert Map.has_key?(excluded_cross_join_query.aliases, :base)

      excluded_left_join_query = exclude(query, :left_join)
      assert length(excluded_left_join_query.joins) == original_joins_number - 1
      assert map_size(excluded_left_join_query.aliases) == original_aliases_number - 1
      refute Map.has_key?(excluded_left_join_query.aliases, :blogs_l)
      assert Map.has_key?(excluded_left_join_query.aliases, :base)

      excluded_right_join_query = exclude(query, :right_join)
      assert length(excluded_right_join_query.joins) == original_joins_number - 1
      assert map_size(excluded_right_join_query.aliases) == original_aliases_number - 1
      refute Map.has_key?(excluded_right_join_query.aliases, :blogs_r)
      assert Map.has_key?(excluded_right_join_query.aliases, :base)

      excluded_full_join_query = exclude(query, :full_join)
      assert length(excluded_full_join_query.joins) == original_joins_number - 1
      assert map_size(excluded_full_join_query.aliases) == original_aliases_number - 1
      refute Map.has_key?(excluded_full_join_query.aliases, :blogs_f)
      assert Map.has_key?(excluded_full_join_query.aliases, :base)

      excluded_inner_lateral_join_query = exclude(query, :inner_lateral_join)
      assert length(excluded_inner_lateral_join_query.joins) == original_joins_number - 1
      assert map_size(excluded_inner_lateral_join_query.aliases) == original_aliases_number - 1
      refute Map.has_key?(excluded_inner_lateral_join_query.aliases, :blogs_il)
      assert Map.has_key?(excluded_inner_lateral_join_query.aliases, :base)

      excluded_left_lateral_join_query = exclude(query, :left_lateral_join)
      assert length(excluded_left_lateral_join_query.joins) == original_joins_number - 1
      assert map_size(excluded_left_lateral_join_query.aliases) == original_aliases_number - 1
      refute Map.has_key?(excluded_left_lateral_join_query.aliases, :blogs_ll)
      assert Map.has_key?(excluded_left_lateral_join_query.aliases, :base)

      excluded_all_joins_query = exclude(query, :join)
      assert excluded_all_joins_query.joins == []
      assert Map.has_key?(excluded_all_joins_query.aliases, :base)
    end
  end

  describe "dynamic/2" do
    test "can be used to merge two dynamics" do
      left = dynamic([posts], posts.is_public == true)
      right = dynamic([posts], posts.is_draft == false)

      assert inspect(dynamic(^left and ^right)) ==
        inspect(dynamic([posts], posts.is_public == true and posts.is_draft == false))

      assert inspect(dynamic(^left or ^right)) ==
        inspect(dynamic([posts], posts.is_public == true or posts.is_draft == false))
    end

    test "can be used to merge dynamics with subquery" do
      subquery =
        from c in "comments",
          where: c.commented_by == ^Ecto.UUID.generate(),
          select: c.post_id

      dynamic = dynamic([posts], posts.is_public == true)
      dynamic_with_subquery = dynamic([posts], posts.id in subquery(subquery))

      assert inspect(dynamic(^dynamic and ^dynamic_with_subquery)) ==
        inspect(dynamic([posts], posts.is_public == true and posts.id in subquery(subquery)))

      assert inspect(dynamic(^dynamic_with_subquery or ^dynamic)) ==
        inspect(dynamic([posts], posts.id in subquery(subquery) or posts.is_public == true))
    end

    test "can be used to merge two dynamics with named bindings" do
      left = dynamic([post: post], post.is_public == true)
      right = dynamic([post: post], post.is_draft == false)

      query = from p in "post", as: :post

      assert inspect(where(query, ^dynamic(^left and ^right))) ==
        inspect(where(query, [post: post], post.is_public == true and post.is_draft == false))
    end

    test "can be used to merge two dynamics with subquery that reuse named binding" do
      subquery =
        from c in "comments",
          where: c.commented_by == ^Ecto.UUID.generate(),
          select: c.post_id

      dynamic = dynamic([post: post], post.is_public == ^true)
      dynamic_with_subquery = dynamic([post: post], post.id in subquery(subquery))
      dynamic_not_in = dynamic([post: post], post.foo not in ^[1, 2, 3])

      query = from p in "post", as: :post

      assert inspect(where(query, ^dynamic(^dynamic and ^dynamic_with_subquery))) ==
        inspect(where(query, [post: post], post.is_public == ^true and post.id in subquery(subquery)))

      assert inspect(where(query, ^dynamic(^dynamic_with_subquery or ^dynamic))) ==
        inspect(where(query, [post: post], post.id in subquery(subquery) or post.is_public == ^true))

      assert inspect(where(query, ^dynamic(^dynamic_with_subquery and ^dynamic and ^dynamic_not_in))) ==
        inspect(where(query, [post: post], post.id in subquery(subquery) and post.is_public == ^true and post.foo not in ^[1, 2, 3]))
    end

    test "merges with precedence" do
      left = dynamic([posts], posts.is_public == true)
      right = dynamic([posts], posts.is_draft == false)

      assert inspect(dynamic(^left or ^left and ^right)) ==
        inspect(dynamic([posts], posts.is_public == true or (posts.is_public == true and posts.is_draft == false)))

      assert inspect(dynamic(^left and ^left or ^right)) ==
        inspect(dynamic([posts], (posts.is_public == true and posts.is_public == true) or posts.is_draft == false))
    end
  end

  describe "fragment/1" do
    test "raises at runtime when interpolation is not a keyword list" do
      assert_raise ArgumentError, ~r/fragment\(...\) does not allow strings to be interpolated/s, fn ->
        clause = ["1 = ?"]
        from p in "posts", where: fragment(^clause)
      end
    end

    test "raises at runtime when interpolation is a binary string" do
      assert_raise ArgumentError, ~r/fragment\(...\) does not allow strings to be interpolated/, fn ->
        clause = "1 = ?"
        from p in "posts", where: fragment(^clause)
      end
    end

    test "supports literals" do
      query = from p in "posts", select: fragment("? COLLATE ?", p.name, literal(^"es_ES"))
      assert {:fragment, _, parts} = query.select.expr

      assert [
               raw: "",
               expr: {{:., _, [{:&, _, [0]}, :name]}, _, _},
               raw: " COLLATE ",
               expr: {:literal, _, ["es_ES"]},
               raw: ""
             ] = parts

      assert_raise ArgumentError, "literal(^value) expects `value` to be a string, got `123`", fn ->
        from p in "posts", select: fragment("? COLLATE ?", p.name, literal(^123))
      end
    end

    test "keeps UTF-8 encoding" do
      assert inspect(from p in "posts", where: fragment("héllò")) ==
             ~s[#Ecto.Query<from p0 in \"posts\", where: fragment("héllò")>]
    end
  end

  describe "has_named_binding?/1" do
    test "returns true if query has a named binding" do
      query =
        from(p in "posts", as: :posts,
          join: b in "blogs",
          join: c in "comments", as: :comment,
          join: l in "links", on: l.valid, as: :link)

      assert has_named_binding?(query, :posts)
      assert has_named_binding?(query, :comment)
      assert has_named_binding?(query, :link)
    end

    test "returns false if query does not have a named binding" do
      query = from(p in "posts")
      refute has_named_binding?(query, :posts)
    end

    test "returns false when query is a tuple, atom or binary" do
      refute has_named_binding?({:foo, :bar}, :posts)
      refute has_named_binding?(:foo, :posts)
      refute has_named_binding?("foo", :posts)
    end

    test "casts queryable to query" do
      assert_raise Protocol.UndefinedError,
                   ~r"protocol Ecto.Queryable not implemented for \[\]",
                   fn -> has_named_binding?([], :posts) end
    end
  end

  describe "reverse_order/1" do
    test "reverses the order of a simple query" do
      order_bys = [asc: :inserted_at, desc: :id]
      reversed_order_bys = [desc: :inserted_at, asc: :id]
      q = from(p in "posts")
      assert inspect(reverse_order(order_by(q, ^order_bys))) ==
             inspect(order_by(q, ^reversed_order_bys))
    end

    test "reverses by primary key with no order" do
      q = from(p in Schema)
      assert inspect(reverse_order(q)) == inspect(order_by(q, desc: :id))
    end
  end
end
