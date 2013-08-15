defmodule Ecto.Query.SelectBuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query.SelectBuilder

  test "escape" do
    assert Macro.escape(quote do &0 end) ==
           escape(quote do x end, [:x])

    assert Macro.escape(quote do &0.y end) ==
           escape(quote do x.y end, [:x])

    assert { Macro.escape(quote do &0.y end), Macro.escape(quote do &0.z end) } ==
           escape(quote do {x.y, x.z} end, [:x])

    assert [Macro.escape(quote do &0.y end), Macro.escape(quote do &0.z end)] ==
           escape(quote do [x.y, x.z] end, [:x])

    assert { Macro.escape(quote do &0.y end), 1 } ==
            escape(quote do {x.y, 1} end, [:x])

    assert Macro.escape(quote do 2 * &0.y end) ==
            escape(quote do 2 * x.y end, [:x])

    assert { :+, _, [{ :x, _, _ }, { :y, _, _ }] } =
            escape(quote do ^(x + y) end, [])

    assert (quote do x.y end) ==
            escape(quote do ^x.y end, [])
  end
end
