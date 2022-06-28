defmodule Ecto.Query.Builder.OrderByTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.OrderBy
  doctest Ecto.Query.Builder.OrderBy

  import Ecto.Query

  describe "escape" do
    test "handles expressions and params" do
      assert {Macro.escape(quote do [asc: &0.y()] end), {[], %{}}} ==
             escape(:order_by, quote do x.y() end, {[], %{}}, [x: 0], __ENV__)

      assert {Macro.escape(quote do [asc: &0.x(), asc: &1.y()] end), {[], %{}}} ==
             escape(:order_by, quote do [x.x(), y.y()] end, {[], %{}}, [x: 0, y: 1], __ENV__)

      assert {Macro.escape(quote do [asc: &0.x(), desc: &1.y()] end), {[], %{}}} ==
             escape(:order_by, quote do [asc: x.x(), desc: y.y()] end, {[], %{}}, [x: 0, y: 1], __ENV__)

      assert {Macro.escape(quote do [asc: &0.x(), desc: &1.y()] end), {[], %{}}} ==
             escape(:order_by, quote do [x.x(), desc: y.y()] end, {[], %{}}, [x: 0, y: 1], __ENV__)

      assert {Macro.escape(quote do [asc: &0.x()] end), {[], %{}}} ==
             escape(:order_by, quote do :x end, {[], %{}}, [x: 0], __ENV__)

      assert {Macro.escape(quote do [asc: &0.x(), desc: &0.y()] end), {[], %{}}} ==
             escape(:order_by, quote do [:x, desc: :y] end, {[], %{}}, [x: 0], __ENV__)

      assert {Macro.escape(quote do [asc_nulls_first: &0.x(), desc_nulls_first: &0.y()] end), {[], %{}}} ==
             escape(:order_by, quote do [asc_nulls_first: :x, desc_nulls_first: :y] end, {[], %{}}, [x: 0], __ENV__)

      assert {Macro.escape(quote do [asc_nulls_last: &0.x(), desc_nulls_last: &0.y()] end), {[], %{}}} ==
             escape(:order_by, quote do [asc_nulls_last: :x, desc_nulls_last: :y] end, {[], %{}}, [x: 0], __ENV__)

      import Kernel, except: [>: 2]
      assert {Macro.escape(quote do [asc: 1 > 2] end), {[], %{}}} ==
             escape(:order_by, quote do 1 > 2 end, {[], %{}}, [], __ENV__)
    end

    test "raises on unbound variables" do
      assert_raise Ecto.Query.CompileError, ~r"unbound variable `x` in query", fn ->
        escape(:order_by, quote do x.y end, {[], %{}}, [], __ENV__)
      end
    end

    test "raises on unknown expression" do
      message = ~r":desc_nulls_first or interpolated value in `order_by`, got: `:test`"
      assert_raise Ecto.Query.CompileError, message, fn ->
        escape(:order_by, quote do [test: x.y] end, {[], %{}}, [x: 0], __ENV__)
      end
    end
  end

  describe "at runtime" do
    test "accepts fields, lists or keyword lists" do
      key = :title
      dir = :desc
      assert order_by("q", [q], ^key).order_bys == order_by("q", [q], [asc: q.title]).order_bys
      assert order_by("q", [q], [^key]).order_bys == order_by("q", [q], [asc: q.title]).order_bys
      assert order_by("q", [q], [desc: ^key]).order_bys == order_by("q", [q], [desc: q.title]).order_bys
      assert order_by("q", [q], [{^dir, ^key}]).order_bys == order_by("q", [q], [desc: q.title]).order_bys
    end

    test "supports dynamic expressions" do
      order_by = [
        asc: dynamic([p], p.foo == ^1 and p.bar == ^"bar"),
        desc: :bar,
        asc: dynamic([p], p.baz == ^2 and p.bat == ^"bat")
      ]

      %{order_bys: [order_by]} = order_by("posts", ^order_by)
      assert Macro.to_string(order_by.expr) ==
             "[asc: &0.foo() == ^0 and &0.bar() == ^1, desc: &0.bar(), asc: &0.baz() == ^2 and &0.bat() == ^3]"
      assert order_by.params ==
             [{1, {0, :foo}}, {"bar", {0, :bar}}, {2, {0, :baz}}, {"bat", {0, :bat}}]
    end

    test "raises on invalid direction" do
      assert_raise ArgumentError, ~r"expected one of :asc,", fn ->
        temp = :temp
        order_by("posts", [p], [{^var!(temp), p.y}])
      end
    end

    test "raises on invalid field" do
      message = "expected a field as an atom in `order_by`, got: `\"temp\"`"
      assert_raise ArgumentError, message, fn ->
        temp = "temp"
        order_by("posts", [p], [asc: ^temp])
      end

      assert_raise ArgumentError, ~r"To use dynamic expressions", fn ->
        dynamic_expr = dynamic([p], p.foo == ^1)
        order_by("posts", [p], [asc: ^dynamic_expr])
      end
    end

    test "raises on invalid interpolation" do
      message = ~r"`order_by` interpolated on root expects a field or a keyword list"
      assert_raise ArgumentError, message, fn ->
        temp = "temp"
        order_by("posts", [p], ^temp)
      end
    end
  end
end
