Code.require_file "../../test_helper.exs", __DIR__

defmodule Ecto.Query.SelectBuilderTest do
  use ExUnit.Case

  import Ecto.Query.SelectBuilder

  test "escape" do
    assert { :single, Macro.escape(quote do x.y end) } ==
           escape(quote do x.y end, [:x])

    assert { :tuple, [Macro.escape(quote do x.y end), Macro.escape(quote do x.z end)] } ==
           escape(quote do {x.y, x.z} end, [:x])

    assert { :list, [Macro.escape(quote do x.y end), Macro.escape(quote do x.z end)] } ==
           escape(quote do [x.y, x.z] end, [:x])
  end

  test "escape raise" do
    message = "only dotted expressions of bound vars are allowed `bound.field`"

    assert_raise ArgumentError, message, fn ->
      escape(quote do 1+2 end, [])
    end

    assert_raise ArgumentError, message, fn ->
      escape(quote do {x.y, 1} end, [:x])
    end

    assert_raise ArgumentError, message, fn ->
      escape(quote do {x.y, {x.z}} end, [:x])
    end

    assert_raise ArgumentError, message, fn ->
      escape(quote do x.y + x.z end, [:x])
    end
  end
end
