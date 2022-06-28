defmodule Ecto.Query.Builder.DistinctTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Distinct
  doctest Ecto.Query.Builder.Distinct

  import Ecto.Query

  describe "escape" do
    test "handles expressions and params" do
      assert {true, {[], %{}}} ==
             escape(true, {[], %{}}, [x: 0], __ENV__)

      assert {Macro.escape(quote do [asc: &0.y()] end), {[], %{}}} ==
             escape(quote do x.y() end, {[], %{}}, [x: 0], __ENV__)

      assert {Macro.escape(quote do [asc: &0.x(), asc: &1.y()] end), {[], %{}}} ==
             escape(quote do [x.x(), y.y()] end, {[], %{}}, [x: 0, y: 1], __ENV__)

      assert {Macro.escape(quote do [asc: &0.x(), desc: &1.y()] end), {[], %{}}} ==
             escape(quote do [x.x(), desc: y.y()] end, {[], %{}}, [x: 0, y: 1], __ENV__)

      import Kernel, except: [>: 2]
      assert {Macro.escape(quote do [asc: 1 > 2] end), {[], %{}}} ==
             escape(quote do 1 > 2 end, {[], %{}}, [], __ENV__)
    end

    test "raises on unbound variables" do
      assert_raise Ecto.Query.CompileError, ~r"unbound variable `x` in query", fn ->
        escape(quote do x.y end, {[], %{}}, [], __ENV__)
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
      assert distinct("q", [q], ^kw).distinct == distinct("q", [q], [desc: q.title]).distinct
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

    test "raises on non-atoms" do
      message = "expected a field as an atom in `distinct`, got: `\"temp\"`"
      assert_raise ArgumentError, message, fn ->
        temp = "temp"
        distinct("posts", [p], [^temp])
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
