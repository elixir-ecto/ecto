defmodule Ecto.Query.OrderByBuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query.OrderByBuilder

  test "escape" do
    varx = { :{}, [], [:&, [], [0]] }
    vary = { :{}, [], [:&, [], [1]] }
    assert [{ :{}, [], [nil, varx, :y] }] ==
           escape(quote do x.y end, [:x])

    assert [{ :{}, [], [nil, varx, :x] }, { :{}, [], [nil, vary, :y] }] ==
           escape(quote do [x.x, y.y] end, [:x, :y])

    assert [{ :{}, [], [:asc, varx, :x] }, { :{}, [], [:desc, vary, :y] }] ==
           escape(quote do [asc: x.x, desc: y.y] end, [:x, :y])
  end

  test "escape raise" do
    assert_raise Ecto.InvalidQueryError, "unbound variable `x` in query", fn ->
      escape(quote do x.y end, [])
    end

    message = "non-allowed direction `test`, only `asc` and `desc` allowed"
    assert_raise Ecto.InvalidQueryError, message, fn ->
      escape(quote do [test: x.y] end, [:x])
    end

    message = "malformed order_by query"
    assert_raise Ecto.InvalidQueryError, message, fn ->
      escape(quote do 1 + 2 end, [])
    end
  end
end
