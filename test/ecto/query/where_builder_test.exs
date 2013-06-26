Code.require_file "../../test_helper.exs", __DIR__

defmodule Ecto.Query.WhereBuilderTest do
  use ExUnit.Case

  import Ecto.Query.WhereBuilder

  test "escape" do
    assert Macro.escape(quote do 1 == 2 end) ==
           escape(quote do 1 == 2 end, [])

    assert (quote do [] ++ [] end) ==
           escape(quote do [] ++ [] end, [])

    assert (quote do x end) ==
           escape(quote do x end, [])

    assert (quote do x.y end) ==
           escape(quote do x.y end, [])

    assert Macro.escape(quote do x.y end) ==
           escape(quote do x.y end, [:x])
  end

  test "escape raise" do
    message = "bound vars are only allowed in dotted expression `x.field` " <>
              "or as argument to a query expression"

    assert_raise ArgumentError, message, fn ->
      escape(quote do x end, [:x])
    end

    assert_raise ArgumentError, message, fn ->
      escape(quote do x.y(0) end, [:x])
    end

    assert_raise ArgumentError, message, fn ->
      escape(quote do foreign(x.y) end, [:x])
    end
  end
end
