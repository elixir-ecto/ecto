defmodule Ecto.Query.Builder.GroupByTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.GroupBy
  doctest Ecto.Query.Builder.GroupBy

  import Ecto.Query

  describe "escape" do
    test "handles expressions and params" do
      assert {Macro.escape(quote(do: [&0.y()])), {[], %{}}} ==
               escape(:group_by, quote(do: x.y()), {[], %{}}, [x: 0], __ENV__)

      assert {Macro.escape(quote(do: [&0.x(), &1.y()])), {[], %{}}} ==
               escape(:group_by, quote(do: [x.x(), y.y()]), {[], %{}}, [x: 0, y: 1], __ENV__)

      import Kernel, except: [>: 2]

      assert {Macro.escape(quote(do: [1 > 2])), {[], %{}}} ==
               escape(:group_by, quote(do: 1 > 2), {[], %{}}, [], __ENV__)
    end

    test "raises on unbound variables" do
      message = ~r"unbound variable `x` in query"

      assert_raise Ecto.Query.CompileError, message, fn ->
        escape(:group_by, quote(do: x.y), {[], %{}}, [], __ENV__)
      end
    end

    test "can reference the alias of a selected value with selected_as/1" do
      query = from p in "posts", select: selected_as(p.id, :ident), group_by: selected_as(:ident)
      assert [{:selected_as, [], [:ident]}] = hd(query.group_bys).expr
    end

    test "raises if name given to selected_as/1 is not an atom" do
      message = "expected literal atom or interpolated value in selected_as/1, got: `\"ident\"`"

      assert_raise Ecto.Query.CompileError, message, fn ->
        escape(:group_by, quote(do: selected_as("ident")), {[], %{}}, [], __ENV__)
      end
    end
  end

  describe "at runtime" do
    test "accepts a field or a list of fields" do
      key = :title
      assert group_by("q", [q], ^key).group_bys == group_by("q", [q], [q.title]).group_bys
      assert group_by("q", [q], [^key]).group_bys == group_by("q", [q], [q.title]).group_bys
    end

    test "accepts dynamics" do
      key = dynamic([p], p.title)
      assert group_by("q", [q], ^key).group_bys == group_by("q", [q], [q.title]).group_bys
      assert group_by("q", [q], ^[key]).group_bys == group_by("q", [q], [q.title]).group_bys
    end

    test "accepts subqueries" do
      key = dynamic([p], exists(from other_q in "q", where: other_q.title == parent_as(:q).title))
      assert [group_by] = group_by("q", [q], ^key).group_bys

      assert group_by.expr == [{:exists, [], [{:subquery, 0}]}]
      assert [_] = group_by.subqueries

      assert [group_by] =
               group_by(
                 "q",
                 [q],
                 exists(from other_q in "q", where: other_q.title == parent_as(:q).title)
               ).group_bys

      assert group_by.expr == [{:exists, [], [{:subquery, 0}]}]
      assert [_] = group_by.subqueries
    end

    test "raises when no a field or a list of fields" do
      message = "expected a field as an atom in `group_by`, got: `\"temp\"`"

      assert_raise ArgumentError, message, fn ->
        temp = "temp"
        group_by("posts", [p], [^Process.get(:unused, temp)])
      end

      message = "expected a list of fields and dynamics in `group_by`, got: `\"temp\"`"

      assert_raise ArgumentError, message, fn ->
        temp = "temp"
        group_by("posts", [p], ^Process.get(:unused, temp))
      end
    end

    test "supports interpolated atom names in selected_as/1" do
      query = from p in "posts", select: selected_as(p.id, :ident), group_by: selected_as(^:ident)
      assert [{:selected_as, [], [:ident]}] = hd(query.group_bys).expr

      message = "expected atom in selected_as/1, got: `\"ident\"`"

      assert_raise Ecto.Query.CompileError, message, fn ->
        from p in "posts", select: selected_as(p.id, :ident), group_by: selected_as(^"ident")
      end
    end
  end
end
