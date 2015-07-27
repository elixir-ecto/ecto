defmodule Ecto.Query.Builder.GroupByTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.GroupBy
  doctest Ecto.Query.Builder.GroupBy

  test "escape" do
    assert {Macro.escape(quote do [&0.y] end), %{}} ==
           escape(quote do x.y end, [x: 0], __ENV__)

    assert {Macro.escape(quote do [&0.x, &1.y] end), %{}} ==
           escape(quote do [x.x, y.y] end, [x: 0, y: 1], __ENV__)

    import Kernel, except: [>: 2]
    assert {Macro.escape(quote do [1 > 2] end), %{}} ==
           escape(quote do 1 > 2 end, [], __ENV__)
  end

  test "escape raise" do
    assert_raise Ecto.Query.CompileError, "unbound variable `x` in query", fn ->
      escape(quote do x.y end, [], __ENV__)
    end
  end
end
