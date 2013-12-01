defmodule Ecto.Query.GroupByBuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query.GroupByBuilder
  doctest Ecto.Query.GroupByBuilder

  test "escape" do
    varx = { :{}, [], [:&, [], [0]] }
    vary = { :{}, [], [:&, [], [1]] }

    assert [{ varx, :y }] ==
           escape(quote do x.y end, [:x])

    assert [{ varx, :x }, { vary, :y }] ==
           escape(quote do [x.x, y.y] end, [:x, :y])

    assert varx ==
           escape(quote do x end, [:x])
  end

  test "escape raise" do
    assert_raise Ecto.QueryError, "unbound variable `x` in query", fn ->
      escape(quote do x.y end, [])
    end

    message = "malformed `group_by` query expression"
    assert_raise Ecto.QueryError, message, fn ->
      escape(quote do 1 + 2 end, [])
    end
  end
end
