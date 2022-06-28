defmodule Ecto.Query.Builder.SelectTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto.Query.Builder.Select
  doctest Ecto.Query.Builder.Select

  defp params_acc(opts \\ []) do
    params = opts[:params] || []
    take = opts[:take] || %{}
    subqueries = opts[:subqueries] || []
    {params, %{take: take, subqueries: subqueries}}
  end

  describe "escape" do
    test "handles expressions and params" do
      assert {Macro.escape(quote do &0 end), params_acc()} ==
             escape(quote do x end, [x: 0], __ENV__)

      assert {Macro.escape(quote do &0.y() end), params_acc()} ==
             escape(quote do x.y() end, [x: 0], __ENV__)

      assert {Macro.escape(quote do &0 end), params_acc(take: %{0 => {:any, [:foo, :bar, baz: :bat]}})} ==
             escape(quote do [:foo, :bar, baz: :bat] end, [x: 0], __ENV__)

      assert {Macro.escape(quote do &0 end), params_acc(take: %{0 => {:struct, [:foo, :bar, baz: :bat]}})} ==
             escape(quote do struct(x, [:foo, :bar, baz: :bat]) end, [x: 0], __ENV__)

      assert {Macro.escape(quote do &0 end), params_acc(take: %{0 => {:map, [:foo, :bar, baz: :bat]}})} ==
             escape(quote do map(x, [:foo, :bar, baz: :bat]) end, [x: 0], __ENV__)

      assert {{:{}, [], [:{}, [], [0, 1, 2]]}, params_acc()} ==
             escape(quote do {0, 1, 2} end, [], __ENV__)

      assert {{:{}, [], [:%{}, [], [a: {:{}, [], [:&, [], [0]]}]]}, params_acc()} ==
             escape(quote do %{a: a} end, [a: 0], __ENV__)

      assert {{:{}, [], [:%{}, [], [{{:{}, [], [:&, [], [0]]}, {:{}, [], [:&, [], [1]]}}]]}, params_acc()} ==
             escape(quote do %{a => b} end, [a: 0, b: 1], __ENV__)

      assert {[Macro.escape(quote do &0.y() end), Macro.escape(quote do &0.z() end)], params_acc()} ==
             escape(quote do [x.y(), x.z()] end, [x: 0], __ENV__)

      assert {[{:{}, [], [{:{}, [], [:., [], [{:{}, [], [:&, [], [0]]}, :y]]}, [], []]},
               {:{}, [], [:^, [], [0]]}], params_acc(params: [{1, :any}])} ==
              escape(quote do [x.y(), ^1] end, [x: 0], __ENV__)

      assert {{:{}, [], [:%, [], [Foo, {:{}, [], [:%{}, [], [a: {:{}, [], [:&, [], [0]]}]]}]]}, params_acc()} ==
             escape(quote do %Foo{a: a} end, [a: 0], __ENV__)
    end

    test "on conflicting take" do
      assert {_, {[], %{take: %{0 => {:map, [:foo, :bar, baz: :bat]}}, subqueries: []}}} =
             escape(quote do {map(x, [:foo, :bar]), map(x, [baz: :bat])} end, [x: 0], __ENV__)

      assert_raise Ecto.Query.CompileError,
                   ~r"cannot select_merge because the binding at position 0",
                   fn ->
        escape(quote do {map(x, [:foo, :bar]), struct(x, [baz: :bat])} end, [x: 0], __ENV__)
      end
    end

    @fields [:field]

    test "supports sigils/attributes" do
      fields = ~w[field]a
      assert select("q", [q], map(q, ~w[field]a)).select.take == %{0 => {:map, fields}}
      assert select("q", [q], struct(q, @fields)).select.take == %{0 => {:struct, fields}}
      assert select("q", [q], ~w[field]a).select.take == %{0 => {:any, fields}}
    end

    test "raises on single atom" do
      assert_raise Ecto.Query.CompileError,
                   ~r":foo is not a valid query expression, :select expects a query expression or a list of fields",
                   fn ->
        escape(quote do :foo end, [x: 0], __ENV__)
      end
    end

    test "raises on mixed fields and interpolation" do
      assert_raise Ecto.Query.CompileError, ~r"Cannot mix fields with interpolations", fn ->
        escape(quote do [:foo, ^:bar] end, [], __ENV__)
      end
    end
  end

  describe "at runtime" do
    test "supports interpolation" do
      fields = [:foo, :bar, :baz]
      assert select("q", ^fields).select.take == %{0 => {:any, fields}}
      assert select("q", [:foo, :bar, :baz]).select == select("q", ^fields).select
      assert select("q", [q], map(q, ^fields)).select.take == %{0 => {:map, fields}}
      assert select("q", [q], struct(q, ^fields)).select.take == %{0 => {:struct, fields}}
    end

    test "supports subqueries" do
      subquery = from(u in "users", where: parent_as(^:list).created_by_id == u.id, select: u.email)

      query =
        from(l in "lists",
          as: :list,
          select: %{title: l.archived_at, user_email: subquery(subquery)}
        )

      assert Macro.to_string(query.select.expr) ==
              "%{title: &0.archived_at(), user_email: {:subquery, 0}}"

      assert length(query.select.subqueries) == 1
      assert length(query.select.params) == 1
    end

    test "supports multiple subqueries" do
      created_by_id = 8

      subquery0 =
        from(t in "tasks",
          where: t.list_id == parent_as(:list).id and t.created_by_id == ^created_by_id,
          select: max(t.due_on)
        )

      subquery1 =
        from(u in "users", where: parent_as(^:list).created_by_id == u.id, select: u.email)

      query =
        from(l in "lists",
          as: :list,
          select: %{
            title: l.archived_at,
            maxdue: subquery(subquery0),
            user_email: subquery(subquery1)
          }
        )

      assert Macro.to_string(query.select.expr) == """
             %{\
             title: &0.archived_at(), \
             maxdue: {:subquery, 0}, \
             user_email: {:subquery, 1}\
             }\
             """

      assert length(query.select.subqueries) == 2
      assert length(query.select.params) == 2
    end

    test "raises on multiple selects" do
      message = "only one select expression is allowed in query"
      assert_raise Ecto.Query.CompileError, message, fn ->
        %Ecto.Query{} |> select([], 1) |> select([], 2)
      end
    end
  end

  describe "select_merge" do
    test "merges at compile time" do
      query =
        from p in "posts",
          select: %{},
          select_merge: %{a: map(p, [:title]), b: ^0},
          select_merge: %{c: map(p, [:title, :body]), d: ^1}

      assert Macro.to_string(query.select.expr) == "merge(%{a: &0, b: ^0}, %{c: &0, d: ^1})"
      assert query.select.params == [{0, :any}, {1, :any}]
      assert query.select.take == %{0 => {:map, [:title, :body]}}
    end

    test "merges at runtime" do
      query =
        "posts"
        |> select([], %{})
        |> select_merge([p], %{a: map(p, [:title]), b: ^0})
        |> select_merge([p], %{c: map(p, [:title, :body]), d: ^1})

      assert Macro.to_string(query.select.expr) == "merge(%{a: &0, b: ^0}, %{c: &0, d: ^1})"
      assert query.select.params == [{0, :any}, {1, :any}]
      assert query.select.take == %{0 => {:map, [:title, :body]}}
    end

    test "merges at the root" do
      query =
        "posts"
        |> select([], %{})
        |> select_merge([p], map(p, [:title]))
        |> select_merge([p], %{body: ^"body"})

      assert Macro.to_string(query.select.expr) == "merge(&0, %{body: ^0})"
      assert query.select.params == [{"body", :any}]
      assert query.select.take == %{0 => {:map, [:title]}}
    end

    test "merges at the root with interpolated fields" do
      fields = [:title]

      query =
        "posts"
        |> select([], %{})
        |> select_merge([p], map(p, ^fields))
        |> select_merge([p], %{body: ^"body"})

      assert Macro.to_string(query.select.expr) == "merge(&0, %{body: ^0})"
      assert query.select.params == [{"body", :any}]
      assert query.select.take == %{0 => {:map, [:title]}}
    end

    test "merges at the root with interpolated fields with explicit merge" do
      fields = [:title]

      query = select("posts", [p], merge(map(p, ^fields), %{body: ^"body"}))
      assert Macro.to_string(query.select.expr) == "merge(&0, %{body: ^0})"
      assert query.select.params == [{"body", :any}]
      assert query.select.take == %{0 => {:map, [:title]}}

      query = select("posts", [p], merge(%{body: ^"body"}, map(p, ^fields)))
      assert Macro.to_string(query.select.expr) == "merge(%{body: ^0}, &0)"
      assert query.select.params == [{"body", :any}]
      assert query.select.take == %{0 => {:map, [:title]}}
    end

    test "merges dynamically" do
      query =
        from(b in "blogs",
          as: :blog,
          join: p in "posts",
          as: :post,
          on: p.blog_id == b.id,
          join: c in "comments",
          as: :comment,
          on: c.post_id == p.id,
          select: %{comments: count(c.id)}
        )

      query =
        Enum.reduce([blog: :name, post: :author], query, fn {binding, field}, query ->
          query
          |> select_merge([{^binding, bound}], %{^field => field(bound, ^field)})
          |> group_by([{^binding, bound}], field(bound, ^field))
        end)

      assert Macro.to_string(query.select.expr) ==
               "merge(merge(%{comments: count(&2.id())}, %{^0 => &0.name()}), %{^1 => &1.author()})"
    end

    test "supports '...' in binding list with no prior select" do
      query =
        "posts"
        |> select_merge([..., p], %{title: p.title})

      assert Macro.to_string(query.select.expr) == "merge(&0, %{title: &0.title()})"
      assert query.select.params == []
      assert query.select.take == %{}
    end

    test "raises on incompatible pairs" do
      assert_raise Ecto.QueryError, ~r/those select expressions are incompatible/, fn ->
        from p in "posts",
          select: %{title: p.title},
          select_merge: %Post{title: nil}
      end
    end

    test "defaults to struct" do
      query = select_merge("posts", [p], %{title: nil})
      assert Macro.to_string(query.select.expr) == "merge(&0, %{title: nil})"
      assert query.select.params == []
      assert query.select.take == %{}
    end

    test "with take" do
      # On select
      query = from p in "posts", select: p, select_merge: [:title]

      assert Macro.to_string(query.select.expr) == "&0"
      assert query.select.params == []
      assert query.select.take == %{}

      # On take
      query = from p in "posts", select: [:body], select_merge: [:title]

      assert Macro.to_string(query.select.expr) == "&0"
      assert query.select.params == []
      assert query.select.take == %{0 => {:any, [:body, :title]}}
    end

    test "on conflicting take" do
      _ = from p in "posts", select: p, select_merge: map(p, [:title]), select_merge: [:body]
      _ = from p in "posts", select: p, select_merge: map(p, [:title]), select_merge: map(p, [:body])
      _ = from p in "posts", select: p, select_merge: [:title], select_merge: map(p, [:body])
      _ = from p in "posts", select: p, select_merge: [:title], select_merge: struct(p, [:body])
      _ = from p in "posts", select: p, select_merge: struct(p, [:title]), select_merge: [:body]
      _ = from p in "posts", select: p, select_merge: struct(p, [:title]), select_merge: struct(p, [:body])

      assert_raise Ecto.Query.CompileError,
                   ~r"cannot select_merge because the binding at position 0",
                   fn ->
        from p in "posts", select: map(p, [:title]), select_merge: struct(p, [:title])
      end
    end

    test "optimizes map/struct merges" do
      query =
        from p in "posts",
          select: %{t: {p.title, p.body}},
          select_merge: %{t: p.title, b: p.body}
      assert Macro.to_string(query.select.expr) == "%{t: &0.title(), b: &0.body()}"

      query =
        from p in "posts",
          select: %Post{title: p.title},
          select_merge: %{title: nil}
      assert Macro.to_string(query.select.expr) == "%Post{title: nil}"

      query =
        from p in "posts",
          select: %{t: {p.title, ^0}},
          select_merge: %{t: p.title, b: p.body}
      assert Macro.to_string(query.select.expr) =~ "merge"
    end
  end
end
