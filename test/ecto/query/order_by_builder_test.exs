defmodule Ecto.Query.OrderByBuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query.OrderByBuilder
  doctest Ecto.Query.OrderByBuilder

  test "escape" do
    assert {Macro.escape(quote do [asc: &0.y] end), %{}} ==
           escape(quote do x.y end, [x: 0])

    assert {Macro.escape(quote do [asc: &0.x, asc: &1.y] end), %{}} ==
           escape(quote do [x.x, y.y] end, [x: 0, y: 1])

    assert {Macro.escape(quote do [asc: &0.x, desc: &1.y] end), %{}} ==
           escape(quote do [asc: x.x, desc: y.y] end, [x: 0, y: 1])

    assert {Macro.escape(quote do [asc: 1 + 2] end), %{}} ==
      escape(quote do 1 + 2 end, [])
  end

  test "escape raise" do
    assert_raise Ecto.QueryError, "unbound variable `x` in query", fn ->
      escape(quote do x.y end, [])
    end

    message = "non-allowed direction `test`, only `asc` and `desc` allowed"
    assert_raise Ecto.QueryError, message, fn ->
      escape(quote do [test: x.y] end, [x: 0])
    end
  end
end
