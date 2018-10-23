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

    test "supports frames" do
      assert {Macro.escape(quote(do: [frame: fragment({:raw, "ROWS 3 PRECEDING EXCLUDE CURRENT ROW"})])), {%{}, :acc}} ==
               escape(quote do [frame: fragment("ROWS 3 PRECEDING EXCLUDE CURRENT ROW")] end, {%{}, :acc}, [], __ENV__)

      start_frame = 3
      assert {Macro.escape(quote(do: [frame: fragment({:raw, "ROWS "}, {:expr, ^0}, {:raw, " PRECEDING"})])),
               {%{0 => {quote(do: start_frame), :any}}, :acc}} ==
               escape(quote do [frame: fragment("ROWS ? PRECEDING", ^start_frame)] end, {%{}, :acc}, [], __ENV__)

      assert_raise Ecto.Query.CompileError, ~r"expected a fragment in `:frame`", fn ->
        escape(quote do [frame: [rows: -3, exclude: :current]] end, {%{}, :acc}, [], __ENV__)
      end
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

    test "allows interpolation on frame" do
      bound = 3
      query = "q" |> windows([p], w: [frame: fragment("ROWS ? PRECEDING EXCLUDE CURRENT ROW", ^bound)])
      assert query.windows[:w].expr[:frame] ==
               {:fragment, [], [raw: "ROWS ", expr: {:^, [], [0]}, raw: " PRECEDING EXCLUDE CURRENT ROW"]}
    end

    test "frame works with over clause" do
      query = "q" |> select([p], over(avg(p.field), [frame: fragment("ROWS 3 PRECEDING")]))
      {:over, [], [_, frame]} = query.select.expr
      assert frame == [frame: {:fragment, [], [raw: "ROWS 3 PRECEDING"]}]
    end
  end
end
