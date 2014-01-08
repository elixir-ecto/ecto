defmodule Ecto.Query.BuilderUtilTest do
  use ExUnit.Case, async: true

  import Ecto.Query.BuilderUtil
  doctest Ecto.Query.BuilderUtil

  test "escape" do
    assert Macro.escape(quote do &0.y end) ==
           escape(quote do x.y end, [:x])

    assert Macro.escape(quote do &0.y + &0.z end) ==
           escape(quote do x.y + x.z end, [:x])

    assert Macro.escape(quote do &0.y + &1.z end) ==
           escape(quote do x.y + y.z end, [:x, :y])

    assert Macro.escape(quote do avg(0) end) ==
           escape(quote do avg(0) end, [])

    assert quote(do: %s"123") ==
           escape(quote do %s"123" end, [])

    assert quote(do: &0.z) ==
           Code.eval_quoted(escape(quote do field(x, ^:z) end, [:x]), [], __ENV__) |> elem(0)
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
    assert_raise Ecto.QueryError, %r"is not a valid query expression", fn ->
      escape(quote do x end, [])
    end

    assert_raise Ecto.QueryError, %r"is not a valid query expression", fn ->
      escape(quote do :atom end, [])
    end

    assert_raise Ecto.QueryError, %r"unbound variable", fn ->
      escape(quote do x.y end, [])
    end

    assert_raise Ecto.QueryError, %r"field name should be an atom", fn ->
      Code.eval_quoted(escape(quote do field(x, 123) end, [:x]), [], __ENV__)
    end
  end

  test "unbound wildcard var" do
    assert_raise Ecto.QueryError, fn ->
      escape(quote do _.y end, [:_, :_])
    end
  end

  test "escape dot" do
    assert Macro.escape(quote(do: { &0, :y })) ==
           escape_dot(quote(do: x.y), [:x])

    assert Macro.escape(quote(do: { &0, :y })) ==
           escape_dot(quote(do: x.y()), [:x])

    assert :error ==
           escape_dot(quote(do: x), [:x])

    assert quote(do: { &0, :y }) ==
           Code.eval_quoted(escape_dot(quote(do: field(x, ^:y)), [:x]), [], __ENV__) |> elem(0)

    assert_raise Ecto.QueryError, %r"field name should be an atom", fn ->
      Code.eval_quoted(escape_dot(quote do field(x, 123) end, [:x]), [], __ENV__)
    end
  end
end
