defmodule Ecto.Query.OrderByBuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query.OrderByBuilder
  doctest Ecto.Query.OrderByBuilder

  test "escape" do
    varx = { :{}, [], [:&, [], [0]] }
    vary = { :{}, [], [:&, [], [1]] }
    assert [{ :{}, [], [:asc, varx, :y] }] ==
           escape(quote do x.y end, [x: 0])

    assert [{ :{}, [], [:asc, varx, :x] }, { :{}, [], [:asc, vary, :y] }] ==
           escape(quote do [x.x, y.y] end, [x: 0, y: 1])

    assert [{ :{}, [], [:asc, varx, :x] }, { :{}, [], [:desc, vary, :y] }] ==
           escape(quote do [asc: x.x, desc: y.y] end, [x: 0, y: 1])
  end

  test "escape raise" do
    assert_raise Ecto.QueryError, "unbound variable `x` in query", fn ->
      escape(quote do x.y end, [])
    end

    message = "non-allowed direction `test`, only `asc` and `desc` allowed"
    assert_raise Ecto.QueryError, message, fn ->
      escape(quote do [test: x.y] end, [x: 0])
    end

    message = "malformed `order_by` query expression"
    assert_raise Ecto.QueryError, message, fn ->
      escape(quote do 1 + 2 end, [])
    end
  end
end
