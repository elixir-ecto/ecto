defmodule Ecto.Query.Builder.FromTest do
  use ExUnit.Case, async: true
  import Ecto.Query.Builder.From
  doctest Ecto.Query.Builder.From

  import Ecto.Query

  defmacro from_macro(left, right) do
    quote do
      fragment("? <> ?", unquote(left), unquote(right))
    end
  end

  test "expands macros as sources" do
    right = "right"

    assert %Ecto.Query.FromExpr{source: {:fragment, [], _}, params: [{"right", :any}]} =
             from(p in from_macro("left", ^right)).from
  end
end
