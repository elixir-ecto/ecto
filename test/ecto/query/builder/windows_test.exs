defmodule Ecto.Query.Builder.WindowsTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Windows
  doctest Ecto.Query.Builder.Windows

  import Ecto.Query

  describe "escape" do
    test "handles expressions and params" do
      assert {Macro.escape(quote do [partition_by: [&0.y]] end), {%{}, :acc}} ==
             escape(quote do [partition_by: x.y] end, {%{}, :acc}, [x: 0], __ENV__)

      assert {Macro.escape(quote do [partition_by: [&0.y]] end), {%{}, :acc}} ==
             escape(quote do [partition_by: :y] end, {%{}, :acc}, [x: 0], __ENV__)

      assert {Macro.escape(quote do [order_by: [asc: &0.y]] end), {%{}, :acc}} ==
             escape(quote do [order_by: x.y] end, {%{}, :acc}, [x: 0], __ENV__)

      assert {Macro.escape(quote do [order_by: [asc: &0.y]] end), {%{}, :acc}} ==
             escape(quote do [order_by: :y] end, {%{}, :acc}, [x: 0], __ENV__)
    end
  end

  describe "at runtime" do
    test "raises on duplicate window" do
      query = "q" |> windows([p], w: [partition_by: p.x])

      assert_raise Ecto.Query.CompileError, ~r"window with name w is already defined", fn ->
        query |> windows([p], w: [partition_by: p.y])
      end
    end

    test "allows interpolation on partition by" do
      fields = [:x]
      query = "q" |> windows([p], w: [partition_by: ^fields])
      assert query.windows[:w].expr[:partition_by] == [{{:., [], [{:&, [], [0]}, :x]}, [], []}]
    end

    test "raises on invalid partition by" do
      assert_raise ArgumentError, ~r"expected a list of fields in `partition_by`", fn ->
        windows("q", w: [partition_by: ^[1]])
      end
    end

    test "allows interpolation on order by" do
      fields = [asc: :x]
      query = "q" |> windows([p], w: [order_by: ^fields])
      assert query.windows[:w].expr[:order_by] == [asc: {{:., [], [{:&, [], [0]}, :x]}, [], []}]
    end

    test "raises on invalid order by" do
      assert_raise ArgumentError, ~r"expected a field as an atom, a list or keyword list in `order_by`", fn ->
        windows("q", w: [order_by: ^[1]])
      end
    end
  end
end
