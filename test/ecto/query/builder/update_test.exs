defmodule Ecto.Query.Builder.UpdateTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto.Query.Builder.Update
  doctest Ecto.Query.Builder.Update

  describe "escape" do
    test "handles expressions and params" do
      assert escape(quote do [set: [foo: 1]] end, [x: 0], __ENV__) |> elem(0) ==
             [set: [foo: {:%, [], [Ecto.Query.Tagged, {:%{}, [], [value: 1, type: {0, :foo}]}]}]]

      assert escape(quote do [set: [foo: x.bar]] end, [x: 0], __ENV__) |> elem(0) ==
             Macro.escape(quote do [set: [foo: &0.bar]] end)
    end

    test "performs compile time interpolation" do
      query = "foo" |> update([p], set: [foo: p.foo == ^1])
      [compile] = query.updates
      assert compile.expr == [set: [foo: {:==, [], [{{:., [], [{:&, [], [0]}, :foo]}, [], []}, {:^, [], [0]}]}]]
      assert compile.params == [{1, {0, :foo}}]
    end

    test "raises on non-keyword lists" do
      assert_raise Ecto.Query.CompileError,
                   ~r"malformed update `\[1\]` in query expression", fn ->
        escape(quote do [1] end, [], __ENV__)
      end

      assert_raise Ecto.Query.CompileError,
                   ~r"malformed :set in update `\[1\]`, expected a keyword list", fn ->
        escape(quote do [set: [1]] end, [], __ENV__)
      end
    end

    test "raises on invalid updates" do
      assert_raise Ecto.Query.CompileError, "unknown key `:unknown` in update", fn ->
        escape(quote do [unknown: [1]] end, [], __ENV__)
      end

      assert_raise Ecto.Query.CompileError, "unknown key `:unknown` in update", fn ->
        update("foo", [_], ^[unknown: [1]])
      end
    end
  end

  describe "at runtime" do
    test "accepts interpolation" do
      query = "foo" |> update([_], ^[set: [foo: "foo", bar: "bar"]])
      [runtime] = query.updates
      assert runtime.expr == [set: [foo: {:^, [], [0]}, bar: {:^, [], [1]}]]
      assert runtime.params == [{"foo", {0, :foo}}, {"bar", {0, :bar}}]

      query = "foo" |> update([_], set: ^[foo: "foo"])
      [runtime] = query.updates
      assert runtime.expr == [set: [foo: {:^, [], [0]}]]
      assert runtime.params == [{"foo", {0, :foo}}]

      query = "foo" |> update([_], set: ^[foo: "foo"], inc: [bar: ^"bar"])
      [runtime] = query.updates
      assert runtime.expr == [set: [foo: {:^, [], [0]}], inc: [bar: {:^, [], [1]}]]
      assert runtime.params == [{"foo", {0, :foo}}, {"bar", {0, :bar}}]

      query = "foo" |> update([_], set: [{^:foo, ^"foo"}])
      [runtime] = query.updates
      assert runtime.expr == [set: [foo: {:^, [], [0]}]]
      assert runtime.params == [{"foo", {0, :foo}}]
    end

    test "accepts dynamic expressions with values" do
      dynamic = dynamic([p], true)

      %{updates: [update]} = update("foo", [_], set: [foo: ^dynamic])
      assert Macro.to_string(update.expr) == "[set: [foo: true]]"
      assert update.params == []

      %{updates: [update]} = update("foo", [_], set: ^[foo: dynamic])
      assert Macro.to_string(update.expr) == "[set: [foo: true]]"
      assert update.params == []

      %{updates: [update]} = update("foo", [_], ^[set: [foo: dynamic]])
      assert Macro.to_string(update.expr) == "[set: [foo: true]]"
      assert update.params == []
    end

    test "accepts dynamic expressions with parameters" do
      dynamic = dynamic([p], ^false and ^true)

      %{updates: [update]} = update("foo", [_], set: [foo: ^1, bar: ^dynamic, baz: ^2])
      assert Macro.to_string(update.expr) == "[set: [foo: ^0, bar: ^1 and ^2, baz: ^3]]"
      assert update.params == [{1, {0, :foo}}, {false, :boolean},
                               {true, :boolean}, {2, {0, :baz}}]
    end

    test "raises on malformed updates" do
      assert_raise ArgumentError, ~r/malformed update/, fn ->
        update("foo", [_], set: ^"bar")
      end

      assert_raise ArgumentError, ~r/malformed :set in update/, fn ->
        update("foo", [_], set: ^["bar"])
      end
    end
  end
end
