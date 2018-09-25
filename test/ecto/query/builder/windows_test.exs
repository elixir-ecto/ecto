defmodule Ecto.Query.Builder.WindowsTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Windows
  doctest Ecto.Query.Builder.Windows

  import Ecto.Query

  describe "at runtime" do
    test "raises on duplicate window" do
      query = "q" |> windows([p], w: [partition_by: p.x])

      assert_raise Ecto.Query.CompileError, ~r"window with name w is already defined", fn ->
        query |> windows([p], w: [partition_by: p.y])
      end
    end

    test "allows interpolation on order by" do
      fields = [asc: :x]
      query = "q" |> windows([p], w: [order_by: ^fields])
      assert query.windows[:w].expr[:order_by] == [asc: {{:., [], [{:&, [], [0]}, :x]}, [], []}]
    end
  end
end
