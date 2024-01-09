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

  test "values list source" do
    # Valid input
    values = [%{num: 1, text: "one"}, %{num: 2, text: "two"}]
    types = %{num: :integer, text: :string}
    query = from v in values(values, types)

    types_kw = Enum.map(types, & &1)
    assert query.from.source == {:values, [], [types_kw, length(values)]}

    # Missing type
    msg = "values/2 must declare the type for every field. The type was not given for field `text`"

    assert_raise ArgumentError, msg, fn ->
      values = [%{num: 1, text: "one"}, %{num: 2, text: "two"}]
      types = %{num: :integer}
      from v in values(values, types)
    end

    # Missing field
    msg = "each member of a values list must have the same fields. Missing field `text` in %{num: 2}"

    assert_raise ArgumentError, msg, fn ->
      values = [%{num: 1, text: "one"}, %{num: 2}]
      types = %{num: :integer, text: :string}
      from v in values(values, types)
    end
  end
end
