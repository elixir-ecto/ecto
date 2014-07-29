defmodule Ecto.Query.DistinctBuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query.DistinctBuilder
  doctest Ecto.Query.DistinctBuilder

  test "escape" do
    assert Macro.escape(quote do [&0.y] end) ==
           escape(quote do x.y end, [x: 0])

    assert Macro.escape(quote do [&0.x, &1.y] end) ==
           escape(quote do [x.x, y.y] end, [x: 0, y: 1])

    assert Macro.escape(quote do [1 + 2] end) ==
      escape(quote do 1 + 2 end, [])
  end

  test "escape raise" do
    assert_raise Ecto.QueryError, "unbound variable `x` in query", fn ->
      escape(quote do x.y end, [])
    end
  end
end
