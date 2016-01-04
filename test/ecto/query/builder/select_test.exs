defmodule Ecto.Query.Builder.SelectTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto.Query.Builder.Select
  doctest Ecto.Query.Builder.Select

  test "escape" do
    assert {Macro.escape(quote do &0 end), {%{}, %{}}} ==
           escape(quote do x end, [x: 0], __ENV__)

    assert {Macro.escape(quote do &0.y end), {%{}, %{}}} ==
           escape(quote do x.y end, [x: 0], __ENV__)

    assert {Macro.escape(quote do &0 end), {%{}, %{0 => [:foo, :bar, baz: :bat]}}} ==
           escape(quote do take(x, [:foo, :bar, baz: :bat]) end, [x: 0], __ENV__)

    assert {{:{}, [], [:{}, [], [0, 1, 2]]}, {%{}, %{}}} ==
           escape(quote do {0, 1, 2} end, [], __ENV__)

    assert {{:{}, [], [:%{}, [], [a: {:{}, [], [:&, [], [0]]}]]}, {%{}, %{}}} ==
           escape(quote do %{a: a} end, [a: 0], __ENV__)

    assert {{:{}, [], [:%{}, [], [{{:{}, [], [:&, [], [0]]}, {:{}, [], [:&, [], [1]]}}]]}, {%{}, %{}}} ==
           escape(quote do %{a => b} end, [a: 0, b: 1], __ENV__)

    assert {[Macro.escape(quote do &0.y end), Macro.escape(quote do &0.z end)], {%{}, %{}}} ==
           escape(quote do [x.y, x.z] end, [x: 0], __ENV__)

    assert {{:{}, [], [:^, [], [0]]}, {%{0 => {{:+, _, [{:x, _, _}, {:y, _, _}]}, :any}}, %{}}} =
            escape(quote do ^(x + y) end, [], __ENV__)

    assert {{:{}, [], [:^, [], [0]]}, {%{0 => {quote do x.y end, :any}}, %{}}} ==
            escape(quote do ^x.y end, [], __ENV__)
  end

  test "only one select is allowed" do
    message = "only one select expression is allowed in query"
    assert_raise Ecto.Query.CompileError, message, fn ->
      %Ecto.Query{} |> select([], 1) |> select([], 2)
    end
  end

  test "select interpolation" do
    fields = [:foo, :bar, :baz]
    assert select("q", [q], take(q, ^fields)).select.take == %{0 => fields}
  end
end
