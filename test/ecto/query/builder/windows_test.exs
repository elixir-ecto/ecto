defmodule Ecto.Query.Builder.WindowsTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Windows
  doctest Ecto.Query.Builder.Windows

  import Ecto.Query

  describe "escape" do
    test "handles expressions and params" do
      assert {Macro.escape(quote do [partition_by: [&0.y()]] end), [], {[], %{}}} ==
             escape(quote do [partition_by: x.y()] end, {[], %{}}, [x: 0], __ENV__)

      assert {Macro.escape(quote do [partition_by: [&0.y()]] end), [], {[], %{}}} ==
             escape(quote do [partition_by: :y] end, {[], %{}}, [x: 0], __ENV__)

      assert {Macro.escape(quote do [order_by: [asc: &0.y()]] end), [], {[], %{}}} ==
             escape(quote do [order_by: x.y()] end, {[], %{}}, [x: 0], __ENV__)

      assert {Macro.escape(quote do [order_by: [asc: &0.y()]] end), [], {[], %{}}} ==
             escape(quote do [order_by: :y] end, {[], %{}}, [x: 0], __ENV__)
    end

    test "supports frames" do
      assert {Macro.escape(quote(do: [frame: fragment({:raw, "ROWS 3 PRECEDING EXCLUDE CURRENT ROW"})])), [], {[], %{}}} ==
               escape(quote do [frame: fragment("ROWS 3 PRECEDING EXCLUDE CURRENT ROW")] end, {[], %{}}, [], __ENV__)

      assert {Macro.escape(quote(do: [frame: fragment({:raw, "ROWS "}, {:expr, ^0}, {:raw, " PRECEDING"})])),
               [], {[{quote(do: start_frame), :any}], %{}}} ==
               escape(quote do [frame: fragment("ROWS ? PRECEDING", ^start_frame)] end, {[], %{}}, [], __ENV__)

      assert_raise Ecto.Query.CompileError, ~r"expected a dynamic or fragment in `:frame`", fn ->
        escape(quote do [frame: [rows: -3, exclude: :current]] end, {[], %{}}, [], __ENV__)
      end
    end
  end

  describe "at compile" do
    test "defines partition_by" do
      query = "q" |> windows([p], w: [partition_by: [p.x]])
      assert query.windows[:w].expr[:partition_by] == [{{:., [], [{:&, [], [0]}, :x]}, [], []}]
    end

    test "defines order by" do
      query = "q" |> windows([p], w: [order_by: [asc: p.x]])
      assert query.windows[:w].expr[:order_by] == [asc: {{:., [], [{:&, [], [0]}, :x]}, [], []}]
    end

    test "defines frame" do
      query = "q" |> windows([p], w: [frame: fragment("FOOBAR")])
      assert query.windows[:w].expr[:frame] == {:fragment, [], [raw: "FOOBAR"]}
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

    test "allows dynamic on partition by" do
      partition_by = [dynamic([p], p.foo == ^"foo")]
      query = "q" |> windows([p], w: [partition_by: ^partition_by])

      assert query.windows[:w].expr[:partition_by] ==
               [{:==, [], [{{:., [], [{:&, [], [0]}, :foo]}, [], []}, {:^, [], [0]}]}]

      assert query.windows[:w].params == [{"foo", {0, :foo}}]
    end

    test "raises on invalid partition by" do
      assert_raise ArgumentError, ~r"expected a list of fields and dynamics in `partition_by`", fn ->
        windows("q", w: [partition_by: ^[1]])
      end
    end

    test "allows interpolation on order by" do
      fields = [asc: :x]
      query = "q" |> windows([p], w: [order_by: ^fields])
      assert query.windows[:w].expr[:order_by] == [asc: {{:., [], [{:&, [], [0]}, :x]}, [], []}]
    end

    test "allows dynamic on order by" do
      order_by = [asc: dynamic([p], p.foo == ^"foo")]
      query = "q" |> windows([p], w: [partition_by: [p.bar == ^"bar"], order_by: ^order_by])

      assert Keyword.keys(query.windows[:w].expr) == [:partition_by, :order_by]

      assert query.windows[:w].expr[:partition_by] ==
               [{:==, [], [{{:., [], [{:&, [], [0]}, :bar]}, [], []}, {:^, [], [0]}]}]

      assert query.windows[:w].expr[:order_by] ==
               [asc: {:==, [], [{{:., [], [{:&, [], [0]}, :foo]}, [], []}, {:^, [], [1]}]}]

      assert query.windows[:w].params == [{"bar", {0, :bar}}, {"foo", {0, :foo}}]
    end

    test "raises on invalid order by" do
      assert_raise ArgumentError, ~r"`order_by` interpolated on root expects a field or a keyword list", fn ->
        windows("q", w: [order_by: ^[1]])
      end
    end

    test "allows dynamic on frame" do
      frame = dynamic(fragment("ROWS ? PRECEDING EXCLUDE CURRENT ROW", ^"foo"))
      query = "q" |> windows([p], w: [partition_by: [p.bar == ^"bar"], order_by: [p.baz], frame: ^frame])

      assert Keyword.keys(query.windows[:w].expr) == [:partition_by, :order_by, :frame]

      assert query.windows[:w].expr[:partition_by] ==
               [{:==, [], [{{:., [], [{:&, [], [0]}, :bar]}, [], []}, {:^, [], [0]}]}]

      assert query.windows[:w].expr[:order_by] ==
               [{:asc, {{:., [], [{:&, [], [0]}, :baz]}, [], []}}]

      assert query.windows[:w].expr[:frame] ==
               {:fragment, [], [raw: "ROWS ", expr: {:^, [], [1]}, raw: " PRECEDING EXCLUDE CURRENT ROW"]}

      assert query.windows[:w].params == [{"bar", {0, :bar}}, {"foo", :any}]
    end

    test "raises on invalid dynamic" do
      assert_raise ArgumentError, "expected a dynamic or fragment in `:frame`, got: `[1]`", fn ->
        windows("q", w: [frame: ^[1]])
      end
    end

    test "static on all" do
      queries = [
        windows("q", [p], w: [partition_by: [p.foo], order_by: [p.bar], frame: fragment("ROWS")]),
        windows("q", [p], w: [order_by: [p.bar], frame: fragment("ROWS"), partition_by: [p.foo]])
      ]

      for query <- queries do
        assert Keyword.keys(query.windows[:w].expr) == [:partition_by, :order_by, :frame]

        assert query.windows[:w].expr[:partition_by] ==
                 [{{:., [], [{:&, [], [0]}, :foo]}, [], []}]

        assert query.windows[:w].expr[:order_by] ==
                 [asc: {{:., [], [{:&, [], [0]}, :bar]}, [], []}]

        assert query.windows[:w].expr[:frame] ==
                 {:fragment, [], [raw: "ROWS"]}
      end
    end

    test "dynamic on all" do
      partition_by = [dynamic([p], p.foo == ^"foo")]
      order_by = [asc: dynamic([p], p.bar == ^"bar")]
      frame = dynamic(fragment("ROWS ? PRECEDING EXCLUDE CURRENT ROW", ^"baz"))

      queries = [
        windows("q", [p], w: [partition_by: ^partition_by, order_by: ^order_by, frame: ^frame]),
        windows("q", [p], w: [order_by: ^order_by, frame: ^frame, partition_by: ^partition_by])
      ]

      for query <- queries do
        assert Keyword.keys(query.windows[:w].expr) == [:partition_by, :order_by, :frame]

        assert query.windows[:w].expr[:partition_by] ==
                 [{:==, [], [{{:., [], [{:&, [], [0]}, :foo]}, [], []}, {:^, [], [0]}]}]

        assert query.windows[:w].expr[:order_by] ==
                 [{:asc, {:==, [], [{{:., [], [{:&, [], [0]}, :bar]}, [], []}, {:^, [], [1]}]}}]

        assert query.windows[:w].expr[:frame] ==
                 {:fragment, [], [raw: "ROWS ", expr: {:^, [], [2]}, raw: " PRECEDING EXCLUDE CURRENT ROW"]}

        assert query.windows[:w].params == [{"foo", {0, :foo}}, {"bar", {0, :bar}}, {"baz", :any}]
      end
    end
  end
end
