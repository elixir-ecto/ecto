defmodule Ecto.Query.Builder.SelectTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto.Query.Builder.Select
  doctest Ecto.Query.Builder.Select

  describe "escape" do
    test "handles expressions and params" do
      assert {Macro.escape(quote do &0 end), {%{}, %{}}} ==
             escape(quote do x end, [x: 0], __ENV__)

      assert {Macro.escape(quote do &0.y end), {%{}, %{}}} ==
             escape(quote do x.y end, [x: 0], __ENV__)

      assert {Macro.escape(quote do &0 end), {%{}, %{0 => {:any, [:foo, :bar, baz: :bat]}}}} ==
             escape(quote do [:foo, :bar, baz: :bat] end, [x: 0], __ENV__)

      assert {Macro.escape(quote do &0 end), {%{}, %{0 => {:struct, [:foo, :bar, baz: :bat]}}}} ==
             escape(quote do struct(x, [:foo, :bar, baz: :bat]) end, [x: 0], __ENV__)

      assert {Macro.escape(quote do &0 end), {%{}, %{0 => {:map, [:foo, :bar, baz: :bat]}}}} ==
             escape(quote do map(x, [:foo, :bar, baz: :bat]) end, [x: 0], __ENV__)

      assert {{:{}, [], [:{}, [], [0, 1, 2]]}, {%{}, %{}}} ==
             escape(quote do {0, 1, 2} end, [], __ENV__)

      assert {{:{}, [], [:%{}, [], [a: {:{}, [], [:&, [], [0]]}]]}, {%{}, %{}}} ==
             escape(quote do %{a: a} end, [a: 0], __ENV__)

      assert {{:{}, [], [:%{}, [], [{{:{}, [], [:&, [], [0]]}, {:{}, [], [:&, [], [1]]}}]]}, {%{}, %{}}} ==
             escape(quote do %{a => b} end, [a: 0, b: 1], __ENV__)

      assert {[Macro.escape(quote do &0.y end), Macro.escape(quote do &0.z end)], {%{}, %{}}} ==
             escape(quote do [x.y, x.z] end, [x: 0], __ENV__)

      assert {[{:{}, [], [{:{}, [], [:., [], [{:{}, [], [:&, [], [0]]}, :y]]}, [], []]},
               {:{}, [], [:^, [], [0]]}], {%{0 => {1, :any}}, %{}}} ==
              escape(quote do [x.y, ^1] end, [x: 0], __ENV__)
    end

    @fields [:field]

    test "supports sigils/attributes" do
      fields = ~w[field]a
      assert select("q", [q], map(q, ~w[field]a)).select.take == %{0 => {:map, fields}}
      assert select("q", [q], struct(q, @fields)).select.take == %{0 => {:struct, fields}}
    end
  end

  describe "at runtime" do
    test "supports interpolation" do
      fields = [:foo, :bar, :baz]
      assert select("q", ^fields).select.take == %{0 => {:any, fields}}
      assert select("q", [q], map(q, ^fields)).select.take == %{0 => {:map, fields}}
      assert select("q", [q], struct(q, ^fields)).select.take == %{0 => {:struct, fields}}
    end

    test "raises on multiple selects" do
      message = "only one select expression is allowed in query"
      assert_raise Ecto.Query.CompileError, message, fn ->
        %Ecto.Query{} |> select([], 1) |> select([], 2)
      end
    end
  end
end
