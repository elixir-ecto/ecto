defmodule Ecto.Query.Builder.SelectTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto.Query.Builder.Select
  doctest Ecto.Query.Builder.Select

  test "escape" do
    assert {Macro.escape(quote do &0 end), %{}} ==
           escape(quote do x end, [x: 0])

    assert {Macro.escape(quote do &0.y end), %{}} ==
           escape(quote do x.y end, [x: 0])

    assert {{:{}, [], [:{}, [], [0, 1, 2]]}, %{}} ==
           escape(quote do {0, 1, 2} end, [])

    assert {[Macro.escape(quote do &0.y end), Macro.escape(quote do &0.z end)], %{}} ==
           escape(quote do [x.y, x.z] end, [x: 0])

    assert {Macro.escape(quote do 2 == &0.y end), %{}} ==
            escape(quote do 2 == x.y end, [x: 0])

    assert {{:{}, [], [:^, [], [0]]}, %{0 => {{:+, _, [{:x, _, _}, {:y, _, _}]}, :any}}} =
            escape(quote do ^(x + y) end, [])

    assert {{:{}, [], [:^, [], [0]]}, %{0 => {quote do x.y end, :any}}} ==
            escape(quote do ^x.y end, [])
  end

  test "escape assoc" do
    assert {Macro.escape(quote do assoc(&0, comments: &1) end), %{}} ==
            escape(quote do assoc(p, comments: c) end, [p: 0, c: 1])

    assert {Macro.escape(quote do assoc(&0, comments: assoc(&1, author: &2), author: &3) end), %{}} ==
            escape(quote do assoc(p, comments: assoc(c, author: cu), author: pu) end, [p: 0, c: 1, cu: 2, pu: 3])

    message = "invalid expression `assoc(var, :hey)` inside `assoc/2` selector"
    assert_raise Ecto.Query.CompileError, message, fn ->
      escape(quote do assoc(var, :hey) end, [:var])
    end
  end

  test "only one select is allowed" do
    message = "only one select expression is allowed in query"
    assert_raise Ecto.Query.CompileError, message, fn ->
      %Ecto.Query{} |> select([], 1) |> select([], 2)
    end
  end
end
