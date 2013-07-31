defmodule Ecto.Query.GroupByBuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query.GroupByBuilder

  test "escape" do
    assert [{ :x, :y }] ==
           escape(quote do x.y end, [:x])

    assert [{ :x, :x }, { :y, :y }] ==
           escape(quote do [x.x, y.y] end, [:x, :y])
  end

  test "escape raise" do
    assert_raise Ecto.InvalidQuery, "unbound variable `x` in query", fn ->
      escape(quote do x.y end, [])
    end

    message = "malformed group_by query"
    assert_raise Ecto.InvalidQuery, message, fn ->
      escape(quote do 1 + 2 end, [])
    end
  end
end
