defmodule Ecto.Query.BuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder
  doctest Ecto.Query.Builder

  defp escape(quoted, vars) do
    escape(quoted, :any, %{}, vars)
  end

  test "escape" do
    assert {Macro.escape(quote do &0.y end), %{}} ==
           escape(quote do x.y end, [x: 0])

    assert {Macro.escape(quote do &0.y == &0.z end), %{}} ==
           escape(quote do x.y == x.z end, [x: 0])

    assert {Macro.escape(quote do &0.y == &1.z end), %{}} ==
           escape(quote do x.y == y.z end, [x: 0, y: 1])

    assert {Macro.escape(quote do avg(0) end), %{}} ==
           escape(quote do avg(0) end, [])

    assert {quote do %unquote(Ecto.Query.Fragment){parts: ["foo"]} end, %{}} ==
           escape(quote do ~f[foo] end, [])

    assert {quote(do: ~s"123"), %{}} ==
           escape(quote do ~s"123" end, [])

    assert {{:%, [], [Ecto.Query.Tagged, {:%{}, [], [value: "abc", type: :uuid]}]}, %{}} ==
           escape(quote do uuid("abc") end, [])

    assert quote(do: &0.z) ==
           escape(quote do field(x, :z) end, [x: 0]) |> elem(0) |> Code.eval_quoted([], __ENV__) |> elem(0)
  end

  test "don't escape interpolation" do
    assert {Macro.escape(quote(do: ^0)), %{0 => quote(do: 1 == 2)}} ==
           escape(quote(do: ^(1 == 2)), [])

    assert {Macro.escape(quote(do: ^0)), %{0 => quote(do: [] ++ [])}} ==
           escape(quote(do: ^([] ++ [])), [])

    assert {Macro.escape(quote(do: ^0 == ^1)), %{0 => 1, 1 => 2}} ==
           escape(quote(do: ^1 == ^2), [])
  end

  test "escape raise" do
    assert_raise Ecto.QueryError, ~r"Variable `x` is not a valid query expression", fn ->
      escape(quote(do: x), [])
    end

    assert_raise Ecto.QueryError, ~r"`:atom` is not a valid query expression", fn ->
      escape(quote(do: :atom), [])
    end

    assert_raise Ecto.QueryError, ~r"`unknown\(1, 2\)` is not a valid query expression", fn ->
      escape(quote(do: unknown(1, 2)), [])
    end

    assert_raise Ecto.QueryError, ~r"unbound variable", fn ->
      escape(quote(do: x.y), [])
    end

    assert_raise Ecto.QueryError, ~r"expected literal atom or interpolated value", fn ->
      escape(quote(do: field(x, 123)), [x: 0]) |> elem(0) |> Code.eval_quoted([], __ENV__)
    end
  end
end
