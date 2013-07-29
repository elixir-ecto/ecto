defmodule Ecto.Query.SelectBuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query.SelectBuilder

  test "escape" do
    assert { { :entity, :x }, Macro.escape(quote do x end) } ==
           escape(quote do x end, [:x])

    assert { :single, Macro.escape(quote do x.y end) } ==
           escape(quote do x.y end, [:x])

    assert { :tuple, [Macro.escape(quote do x.y end), Macro.escape(quote do x.z end)] } ==
           escape(quote do {x.y, x.z} end, [:x])

    assert { :list, [Macro.escape(quote do x.y end), Macro.escape(quote do x.z end)] } ==
           escape(quote do [x.y, x.z] end, [:x])

    assert { :tuple, [Macro.escape(quote do x.y end), 1] } ==
            escape(quote do {x.y, 1} end, [:x])

    assert { :single, Macro.escape(quote do 2 * x.y end) } ==
            escape(quote do 2 * x.y end, [:x])

    assert { :single, { :+, _, [{ :x, _, _ }, { :y, _, _ }] } } =
            escape(quote do x + y end, [])

    assert { :single, quote do x.y end } ==
            escape(quote do x.y end, [])
  end

  test "escape raise" do
    message = "bound vars are only allowed in dotted expression `x.field` or as argument to a query expression"
    assert_raise Ecto.InvalidQuery, message, fn ->
      escape(quote do foreign(x.y) end, [:x])
    end
  end
end
