Code.require_file "../../test_helper.exs", __DIR__

defmodule Ecto.Query.OrderByBuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query.OrderByBuilder

  test "escape" do
    assert [{ :{}, [], [nil, :x, :y] }] ==
           escape(quote do x.y end, [:x])

    assert [{ :{}, [], [nil, :x, :x] }, { :{}, [], [nil, :y, :y] }] ==
           escape(quote do [x.x, y.y] end, [:x, :y])

    assert [{ :{}, [], [:asc, :x, :x] }, { :{}, [], [:desc, :y, :y] }] ==
           escape(quote do [asc: x.x, desc: y.y] end, [:x, :y])
  end

  test "escape raise" do
    assert_raise Ecto.InvalidQuery, "unbound variable `x` in query", fn ->
      escape(quote do x.y end, [])
    end

    message = "non-allowed direction `test`, only `asc` and `desc` allowed"
    assert_raise Ecto.InvalidQuery, message, fn ->
      escape(quote do [test: x.y] end, [:x])
    end

    message = "malformed order_by query"
    assert_raise Ecto.InvalidQuery, message, fn ->
      escape(quote do 1 + 2 end, [])
    end
  end
end
