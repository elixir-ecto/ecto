defmodule Ecto.Query.Builder.OrderByTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.OrderBy
  doctest Ecto.Query.Builder.OrderBy

  import Ecto.Query

  describe "escape" do
    defmacro my_custom_field(p) do
      quote(do: fragment("lower(?)", unquote(p).title))
    end

    defmacro my_custom_order(p) do
      quote do
        [unquote(p).id, my_custom_field(unquote(p)), nth_value(unquote(p).links, 1)]
      end
    end

    defmacro my_complex_order(p) do
      quote(do: [desc: unquote(p).id, asc: my_custom_field(unquote(p)), asc: nth_value(unquote(p).links, 1)])
    end

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

      assert {Macro.escape(quote do [desc: &0.id(), asc: fragment({:raw, "lower("}, {:expr, &0.title()}, {:raw, ")"}), asc: nth_value(&0.links(), 1)] end), {[], %{}}} ==
             escape(:order_by, quote do my_complex_order(x) end, {[], %{}}, [x: 0], __ENV__)

      assert {Macro.escape(quote do [asc: &0.id(), asc: fragment({:raw, "lower("}, {:expr, &0.title()}, {:raw, ")"}), asc: nth_value(&0.links(), 1)] end), {[], %{}}} ==
             escape(:order_by, quote do my_custom_order(x) end, {[], %{}}, [x: 0], __ENV__)

      assert assert {[asc: {:{}, [], [:is_nil, [], [{:{}, [], [:&, [], [0]]}]]}], {[], %{}}} ==
             escape(:order_by, quote do is_nil(x) end, {[], %{}}, [x: 0], __ENV__)
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

    test "can reference the alias of a selected value with selected_as/1" do
      # direction defaults to ascending
      query = from p in "posts", select: selected_as(p.id, :ident), order_by: selected_as(:ident)
      assert [asc: {:selected_as, [], [:ident]}] = hd(query.order_bys).expr

      # direction specified
      query =
        from p in "posts",
          select: selected_as(p.id, :ident),
          order_by: [desc: selected_as(:ident)]

      assert [desc: {:selected_as, [], [:ident]}] = hd(query.order_bys).expr

      query =
        from p in "posts", select: selected_as(p.id, :ident), order_by: [asc: selected_as(:ident)]

      assert [asc: {:selected_as, [], [:ident]}] = hd(query.order_bys).expr

      # expression containing selected_as/1
      query =
        from p in "posts",
          select: %{id: selected_as(p.id, :ident), id2: selected_as(p.id, :ident2)},
          order_by: selected_as(:ident) + selected_as(:ident2)

      assert [asc: {:+, [], [{:selected_as, [], [:ident]}, {:selected_as, [], [:ident2]}]}] = hd(query.order_bys).expr
    end

    test "raises if name given to selected_as/1 is not an atom" do
      message = "expected literal atom or interpolated value in selected_as/1, got: `\"ident\"`"

      assert_raise Ecto.Query.CompileError, message, fn ->
        escape(:order_by, quote do selected_as("ident") end, {[], %{}}, [], __ENV__)
      end

      assert_raise Ecto.Query.CompileError, message, fn ->
        escape(:order_by, quote do [desc: selected_as("ident")] end, {[], %{}}, [], __ENV__)
      end
    end

    test "prepend_order_by" do
      query = order_by("q", [q], [:title])
      %{order_bys: order_bys} = prepend_order_by(query, [q], [:prepend])

      assert [
               %{expr: [asc: {{:., _, [_, :prepend]}, _, _}]},
               %{expr: [asc: {{:., _, [_, :title]}, _, _}]}
             ] = order_bys
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

    test "supports subqueries" do
      order_by = [
        asc: dynamic([p], exists(from other_post in "posts", where: other_post.id == parent_as(:p).id))
      ]

      %{order_bys: [order_by]} = from p in "posts", as: :p, order_by: ^order_by
      assert order_by.expr ==  [asc: {:exists, [], [subquery: 0]}]
      assert [_] = order_by.subqueries

      %{order_bys: [order_by]} = from p in "posts", as: :p, order_by: [asc: exists(from other_post in "posts", where: other_post.id == parent_as(:p).id)]
      assert order_by.expr ==  [asc: {:exists, [], [subquery: 0]}]
      assert [_] = order_by.subqueries
    end

    test "supports interpolated atomnames in selected_as/1" do
      query = from p in "posts", select: selected_as(p.id, :ident), order_by: selected_as(^:ident)
      assert [asc: {:selected_as, [], [:ident]}] = hd(query.order_bys).expr

      message = "expected atom in selected_as/1, got: `\"ident\"`"

      assert_raise Ecto.Query.CompileError, message, fn ->
        from p in "posts", select: selected_as(p.id, :ident), order_by: selected_as(^"ident")
      end
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
