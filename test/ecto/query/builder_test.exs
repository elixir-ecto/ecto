defmodule Ecto.Query.BuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder
  doctest Ecto.Query.Builder

  test "escape" do
    assert {Macro.escape(quote do &0.y end), %{}} ==
           escape(quote do x.y end, [x: 0])

    assert {Macro.escape(quote do &0.y + &0.z end), %{}} ==
           escape(quote do x.y + x.z end, [x: 0])

    assert {Macro.escape(quote do &0.y + &1.z end), %{}} ==
           escape(quote do x.y + y.z end, [x: 0, y: 1])

    assert {Macro.escape(quote do avg(0) end), %{}} ==
           escape(quote do avg(0) end, [])

    assert {quote(do: ~s"123"), %{}} ==
           escape(quote do ~s"123" end, [])

    assert {{:%, [], [Ecto.Tagged, {:%{}, [], [value: {:<<>>, [], [1, 2, 3]}, type: :binary]}]}, %{}} ==
           escape(quote do binary(<< 1, 2, 3 >>) end, [])

    assert %Ecto.Tagged{value: [1, 2, 3], type: {:array, :integer}} ==
           escape(quote do array([1, 2, 3], :integer) end, []) |> elem(0) |> Code.eval_quoted([], __ENV__) |> elem(0)

    assert quote(do: &0.z) ==
           escape(quote do field(x, :z) end, [x: 0]) |> elem(0) |> Code.eval_quoted([], __ENV__) |> elem(0)
  end

  test "don't escape interpolation" do
    assert {Macro.escape(quote(do: ^0)), %{0 => quote(do: 1 == 2)}} ==
           escape(quote(do: ^(1 == 2)), [])

    assert {Macro.escape(quote(do: ^0)), %{0 => quote(do: [] ++ [])}} ==
           escape(quote(do: ^([] ++ [])), [])

    assert {Macro.escape(quote(do: ^0 + ^1)), %{0 => 1, 1 => 2}} ==
           escape(quote(do: ^1 + ^2), [])
  end

  test "escape raise" do
    assert_raise Ecto.QueryError, ~r"is not a valid query expression", fn ->
      escape(quote(do: x), [])
    end

    assert_raise Ecto.QueryError, ~r"is not a valid query expression", fn ->
      escape(quote(do: :atom), [])
    end

    assert_raise Ecto.QueryError, ~r"unbound variable", fn ->
      escape(quote(do: x.y), [])
    end

    assert_raise Ecto.QueryError, ~r"expected literal atom or interpolated value", fn ->
      escape(quote(do: field(x, 123)), [x: 0]) |> elem(0) |> Code.eval_quoted([], __ENV__)
    end

    assert_raise Ecto.QueryError, ~r"expected literal atom or interpolated value", fn ->
      escape(quote(do: array([1, 2, 3], 123)), []) |> elem(0) |> Code.eval_quoted([], __ENV__)
    end
  end

  test "escape dot" do
    assert Macro.escape(quote(do: {&0, :y})) ==
           escape_dot(quote(do: x.y), [x: 0])

    assert Macro.escape(quote(do: {&0, :y})) ==
           escape_dot(quote(do: x.y()), [x: 0])

    assert :error ==
           escape_dot(quote(do: x), [x: 0])

    assert quote(do: {&0, :y}) ==
           Code.eval_quoted(escape_dot(quote(do: field(x, :y)), [x: 0]), [], __ENV__) |> elem(0)

    assert_raise Ecto.QueryError, ~r"expected literal atom or interpolated value", fn ->
      Code.eval_quoted(escape_dot(quote(do: field(x, 123)), [x: 0]), [], __ENV__)
    end
  end

  test "escape_fields_and_vars" do
    varx = {:{}, [], [:&, [], [0]]}
    vary = {:{}, [], [:&, [], [1]]}

    assert [{varx, :y}] ==
           escape_fields_and_vars(quote do x.y end, [x: 0])

    assert [{varx, :x}, {vary, :y}] ==
           escape_fields_and_vars(quote do [x.x, y.y] end, [x: 0, y: 1])

    assert [varx] ==
           escape_fields_and_vars(quote do x end, [x: 0])

    assert [varx, {vary, :x}] ==
           escape_fields_and_vars(quote do [x, y.x] end, [x: 0, y: 1])

    assert [varx, vary] ==
           escape_fields_and_vars(quote do [x, y] end, [x: 0, y: 1])
  end

  test "escape_expr raise" do
    assert_raise Ecto.QueryError, "unbound variable `x` in query", fn ->
      escape_fields_and_vars(quote do x.y end, [])
    end

    message = "malformed query expression"
    assert_raise Ecto.QueryError, message, fn ->
      escape_fields_and_vars(quote do 1 + 2 end, [])
    end
  end
end
