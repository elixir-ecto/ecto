defmodule Ecto.Query.Builder.WindowsTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Windows
  doctest Ecto.Query.Builder.Windows

  import Ecto.Query

  defp escape(quoted, vars, env) do
    {escaped, {params, :acc}} = escape(quoted, {%{}, :acc}, vars, env)
    {escaped, params}
  end

  describe "escape" do
    test "handles expressions and params" do
      assert {Macro.escape(quote do [fields: [&0.x]] end), %{}} ==
             escape(quote do [x.x] end, [x: 0], __ENV__)

      assert {Macro.escape(quote do [fields: [&0.x, &0.y]] end), %{}} ==
             escape(quote do [[x.x, x.y]] end, [x: 0], __ENV__)

      assert {Macro.escape(quote do [fields: [&0.x], order_by: [asc: &0.y]] end), %{}} ==
             escape(quote do [x.x, [order_by: x.y]] end, [x: 0], __ENV__)

      assert {Macro.escape(quote do [fields: [&0.x, &0.z], order_by: [asc: &0.y]] end), %{}} ==
             escape(quote do [[x.x, x.z], [order_by: x.y]] end, [x: 0], __ENV__)

      assert {Macro.escape(quote do [fields: [&0.x], order_by: [asc: &0.y], order_by: [asc: &0.z]] end), %{}} ==
             escape(quote do [x.x, [order_by: x.y, order_by: x.z]] end, [x: 0], __ENV__)
    end

    test "raises on duplicate window" do
      query = "q" |> windows([p], w: partition_by p.x)
      assert_raise Ecto.Query.CompileError, ~r"window with name w is already defined", fn ->
        query |> windows([p], w: partition_by p.y)
      end
    end
  end
end
