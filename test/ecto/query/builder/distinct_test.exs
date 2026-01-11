defmodule Ecto.Query.Builder.DistinctTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Distinct
  doctest Ecto.Query.Builder.Distinct

  import Ecto.Query

  describe "escape" do
    test "handles expressions and params" do
      assert {true, {[], %{}}} ==
               escape(true, {[], %{}}, [x: 0], __ENV__)

      assert {Macro.escape(quote(do: [asc: &0.y()])), {[], %{}}} ==
               escape(quote(do: x.y()), {[], %{}}, [x: 0], __ENV__)

      assert {Macro.escape(quote(do: [asc: &0.x(), asc: &1.y()])), {[], %{}}} ==
               escape(quote(do: [x.x(), y.y()]), {[], %{}}, [x: 0, y: 1], __ENV__)

      assert {Macro.escape(quote(do: [asc: &0.x(), desc: &1.y()])), {[], %{}}} ==
               escape(quote(do: [x.x(), desc: y.y()]), {[], %{}}, [x: 0, y: 1], __ENV__)

      import Kernel, except: [>: 2]

      assert {Macro.escape(quote(do: [asc: 1 > 2])), {[], %{}}} ==
               escape(quote(do: 1 > 2), {[], %{}}, [], __ENV__)
    end

    test "raises on unbound variables" do
      assert_raise Ecto.Query.CompileError, ~r"unbound variable `x` in query", fn ->
        escape(quote(do: x.y), {[], %{}}, [], __ENV__)
      end
    end
  end

  describe "at runtime" do
    test "accepts fields" do
      key = :title
      assert distinct("q", [q], ^key).distinct == distinct("q", [q], [q.title]).distinct
      assert distinct("q", [q], [^key]).distinct == distinct("q", [q], [q.title]).distinct
    end

    test "accepts keyword lists" do
      kw = [desc: :title]
      assert distinct("q", [q], ^kw).distinct == distinct("q", [q], desc: q.title).distinct
    end

    test "accepts the boolean true" do
      bool = true
      assert distinct("q", [q], ^bool).distinct == distinct("q", [q], true).distinct
    end

    test "supports dynamic expressions" do
      order_by = [
        asc: dynamic([p], p.foo == ^1 and p.bar == ^"bar"),
        desc: :bar,
        asc: dynamic([p], p.baz == ^2 and p.bat == ^"bat")
      ]

      %{distinct: distinct} = distinct("posts", ^order_by)

      assert Macro.to_string(distinct.expr) ==
               "[asc: &0.foo() == ^0 and &0.bar() == ^1, desc: &0.bar(), asc: &0.baz() == ^2 and &0.bat() == ^3]"

      assert distinct.params ==
               [{1, {0, :foo}}, {"bar", {0, :bar}}, {2, {0, :baz}}, {"bat", {0, :bat}}]
    end

    test "supports subqueries" do
      distinct = [
        asc:
          dynamic(
            [p],
            exists(from other_post in "posts", where: other_post.id == parent_as(:p).id)
          )
      ]

      %{distinct: distinct} = from p in "posts", as: :p, distinct: ^distinct
      assert distinct.expr == [asc: {:exists, [], [subquery: 0]}]
      assert [_] = distinct.subqueries

      %{distinct: distinct} =
        from p in "posts",
          as: :p,
          distinct: [
            asc: exists(from other_post in "posts", where: other_post.id == parent_as(:p).id)
          ]

      assert distinct.expr == [asc: {:exists, [], [subquery: 0]}]
      assert [_] = distinct.subqueries
    end

    test "raises on non-atoms" do
      message = "expected a field as an atom in `distinct`, got: `\"temp\"`"

      assert_raise ArgumentError, message, fn ->
        temp = "temp"
        distinct("posts", [p], [^Process.get(:unused, temp)])
      end
    end

    test "raises non-lists" do
      message = ~r"`distinct` interpolated on root expects a field or a keyword list"

      assert_raise ArgumentError, message, fn ->
        temp = "temp"
        distinct("posts", [p], ^temp)
      end
    end
  end
end
