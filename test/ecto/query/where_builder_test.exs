Code.require_file "../../test_helper.exs", __DIR__

defmodule Ecto.Query.WhereBuilderTest do
  use ExUnit.Case

  import Ecto.Query.WhereBuilder
  alias Ecto.Query.WhereBuilder.State

  test "escape" do
    assert { Macro.escape(quote do 1 == 2 end), State[] } ==
           escape(quote do 1 == 2 end)

    assert { quote do [] ++ [] end, State[] } ==
           escape(quote do [] ++ [] end)

    assert { { :x, _, __MODULE__ }, State[external: [x: __MODULE__], binding: []] } =
           escape(quote do x end)

    assert { Macro.escape(quote do x.y end),
             State[external: [x: __MODULE__], binding: [x: __MODULE__]] } ==
           escape(quote do x.y end)

    assert { quote do x() end, State[] } ==
           escape(quote do x() end)

    assert { quote do x[:y] end , State[external: [x: __MODULE__], binding: []] } ==
           escape(quote do x[:y] end)

    assert { quote do x.y.z end , State[external: [x: __MODULE__], binding: []] } =
           escape(quote do x.y.z end)

    assert { quote do x.y(0) end , State[external: [x: __MODULE__], binding: []] } =
           escape(quote do x.y(0) end)

    assert { quote do Kernel.y end , State[external: [], binding: []] } =
           escape(quote do Kernel.y end)
  end
end
