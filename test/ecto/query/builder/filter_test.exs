defmodule Ecto.Query.Builder.FilterTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Filter
  doctest Ecto.Query.Builder.Filter

  import Ecto.Query

  describe "escape" do
    test "handles expressions, params" do
      import Kernel, except: [==: 2, and: 2]

      assert escape(:where, quote do [] end, 0, [x: 0], __ENV__) ===
             {true, {[], %{subqueries: []}}}

      assert escape(:where, quote do {x.x()} == {^"foo"} end, 0, [x: 0], __ENV__) ===
             {Macro.escape(quote do {&0.x()} == {^0} end),
             {[{"foo", {0, :x}}], %{subqueries: []}}}

      escaped = Macro.escape(quote do &0.x() == ^0 and &0.y() == ^1 end)
      assert {^escaped, {params, %{}}} =
              escape(:where, quote do [x: ^"foo", y: ^"bar"] end, 0, [x: 0], __ENV__)
      assert [{{_, _, ["bar", :y]}, {0, :y}}, {{_, _, ["foo", :x]}, {0, :x}}] = params
    end

    test "raises on invalid expressions" do
      assert_raise Ecto.Query.CompileError,
                   ~r"expected a keyword list at compile time in where, got: `\[\{1, 2\}\]`", fn ->
        escape(:where, quote do [{1, 2}] end, 0, [], __ENV__)
      end

      assert_raise Ecto.Query.CompileError,
                   ~r"Tuples can only be used in comparisons with literal tuples of the same size", fn ->
        escape(:where, quote do {1, 2} > ^foo end, 0, [], __ENV__)
      end
    end

    test "raises on nils" do
      assert_raise Ecto.Query.CompileError,
                   ~r"nil given for `x`. Comparison with nil is forbidden as it is unsafe.", fn ->
        escape(:where, quote do [x: nil] end, 0, [], __ENV__)
      end
    end
  end

  describe "at runtime" do
    test "accepts empty keyword lists" do
      query = where(from(p in "posts"), [p], ^[])
      assert query.wheres == []
    end

    test "accepts keyword lists" do
      %{wheres: [where]} = where(from(p in "posts"), [p], ^[foo: 1, bar: "baz"])
      assert Macro.to_string(where.expr) ==
             "&0.foo() == ^0 and &0.bar() == ^1"
      assert where.params ==
             [{1, {0, :foo}}, {"baz", {0, :bar}}]
    end

    test "supports dynamic expressions" do
      dynamic = dynamic([p], p.foo == ^1 and p.bar == ^"baz")
      %{wheres: [where]} = where("posts", ^dynamic)
      assert Macro.to_string(where.expr) ==
             "&0.foo() == ^0 and &0.bar() == ^1"
      assert where.params ==
             [{1, {0, :foo}}, {"baz", {0, :bar}}]
    end

    test "in subquery" do
      s = from(p in "posts", select: p.id, where: p.public == ^true)
      %{wheres: [where]} = from(p in "posts", where: p.id in subquery(s))
      assert Macro.to_string(where.expr) ==
             "&0.id() in {:subquery, 0}"
      assert where.params ==
        [{:subquery, 0}]
    end

    test "supports exists subquery expressions" do
      s = from(p in "posts", select: 1)

      %{wheres: [where]} = from(p in "posts", where: exists(s))

      assert Macro.to_string(where.expr) ==
             "exists({:subquery, 0})"
      assert where.params ==
             [{:subquery, 0}]
    end

    test "supports comparison with subqueries with all and any quantifiers" do
      s = from(p in "posts", select: p.rating, order_by: [desc: p.created_at], limit: 10)

      assert_quantified_subquery = fn %{wheres: [where]}, expected_quantifier ->
        assert Macro.to_string(where.expr) ==
               "&0.rating() >= #{expected_quantifier}({:subquery, 0})"

        assert where.params ==
                [{:subquery, 0}]
      end

      all_query = from(p in "posts", where: p.rating >= all(s))
      any_query = from(p in "posts", where: p.rating >= any(s))

      assert_quantified_subquery.(all_query, :all)
      assert_quantified_subquery.(any_query, :any)
    end

    test "supports scalar subqueries anywhere in the expression" do
      s = from(p in "posts", select: avg(p.rating))

      %{wheres: [where]} = from(p in "posts", where: p.rating > subquery(s), select: p.id)

      assert Macro.to_string(where.expr) ==
             "&0.rating() > {:subquery, 0}"
      assert where.params ==
             [{:subquery, 0}]
    end

    test "raises on invalid keywords" do
      assert_raise ArgumentError, fn ->
        where(from(p in "posts"), [p], ^[{1, 2}])
      end
    end

    test "raises on nil" do
      assert_raise ArgumentError, fn ->
        where(from(p in "posts"), [p], ^[foo: nil])
      end
    end

    test "raises on nil when a map-value is accessed" do
      f = fn arg ->
        from(p in "posts", where: p.foo == ^arg.x and p.bar == ^arg.y)
      end

      assert_raise ArgumentError, fn -> f.(%{x: nil, y: "y"}) end
      assert_raise ArgumentError, fn -> f.(%{x: "x", y: nil}) end
    end
  end
end
