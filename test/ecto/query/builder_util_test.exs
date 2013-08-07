defmodule Ecto.Query.BuilderUtilTest do
  use ExUnit.Case, async: true

  import Ecto.Query.BuilderUtil

  test "escape" do
    assert Macro.escape(quote do x.y end) ==
           escape(quote do x.y end, [:x])

    assert Macro.escape(quote do x.y + x.z end) ==
           escape(quote do x.y + x.z end, [:x])

    assert Macro.escape(quote do avg(0) end) ==
           escape(quote do avg(0) end, [])
  end

  test "don't escape interpolation" do
    assert (quote do 1 == 2 end) ==
           escape(quote do ^(1 == 2) end, [])

    assert (quote do [] ++ [] end) ==
           escape(quote do ^([] ++ []) end, [])

    assert (quote do 1 + 2 + 3 + 4 end) ==
           escape(quote do ^(1 + 2 + 3 + 4) end, [])
  end

  test "escape raise" do
    message = %r"is not a valid query expression"

    assert_raise Ecto.InvalidQuery, message, fn ->
      escape(quote do x end, [])
    end

    assert_raise Ecto.InvalidQuery, message, fn ->
      escape(quote do :atom end, [])
    end

    message = %r"needs to be bound in a from expression"

    assert_raise Ecto.InvalidQuery, message, fn ->
      escape(quote do x.y end, [])
    end
  end

  test "unbound wildcard var" do
    assert_raise Ecto.InvalidQuery, fn ->
      escape(quote do _.y end, [:_, :_])
    end
  end
end
