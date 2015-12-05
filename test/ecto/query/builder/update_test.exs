defmodule Ecto.Query.Builder.UpdateTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto.Query.Builder.Update
  doctest Ecto.Query.Builder.Update

  test "escape" do
    assert escape(quote do [set: [foo: 1]] end, [x: 0], __ENV__) |> elem(0) ==
           [set: [foo: {:%, [], [Ecto.Query.Tagged, {:%{}, [], [value: 1, type: {0, :foo}]}]}]]

    assert escape(quote do [set: [foo: x.bar]] end, [x: 0], __ENV__) |> elem(0) ==
           Macro.escape(quote do [set: [foo: &0.bar]] end)
  end

  test "escape with compile time interpolation" do
    query = "foo" |> update([_], set: [foo: ^"foo"])
    [compile] = query.updates
    assert compile.expr == [set: [foo: {:^, [], [0]}]]
    assert compile.params == [{"foo", {0, :foo}}]

    query = "foo" |> update([_], set: [foo: ^"foo", bar: ^"bar"])
    [compile] = query.updates
    assert compile.expr == [set: [foo: {:^, [], [0]}, bar: {:^, [], [1]}]]
    assert compile.params == [{"foo", {0, :foo}}, {"bar", {0, :bar}}]
  end

  test "escape with runtime time interpolation" do
    query = "foo" |> update([_], ^[set: [foo: "foo", bar: "bar"]])
    [runtime] = query.updates
    assert runtime.expr == [set: [foo: {:^, [], [0]}, bar: {:^, [], [1]}]]
    assert runtime.params == [{"foo", {0, :foo}}, {"bar", {0, :bar}}]

    query = "foo" |> update([_], set: ^[foo: "foo"])
    [runtime] = query.updates
    assert runtime.expr == [set: [foo: {:^, [], [0]}]]
    assert runtime.params == [{"foo", {0, :foo}}]

    query = "foo" |> update([_], set: ^[foo: "foo"], inc: ^[bar: "bar"])
    [runtime] = query.updates
    assert runtime.expr == [set: [foo: {:^, [], [0]}], inc: [bar: {:^, [], [1]}]]
    assert runtime.params == [{"foo", {0, :foo}}, {"bar", {0, :bar}}]
  end

  test "escape with both compile and runtime time interpolation" do
    query = "foo" |> update([_], set: ^[foo: "foo"], inc: [bar: ^"bar"])
    [compile, runtime] = query.updates
    assert runtime.expr == [set: [foo: {:^, [], [0]}]]
    assert runtime.params == [{"foo", {0, :foo}}]
    assert compile.expr == [inc: [bar: {:^, [], [0]}]]
    assert compile.params == [{"bar", {0, :bar}}]
  end

  test "runtime values are validated" do
    assert_raise ArgumentError, ~r/malformed update/, fn ->
      update("foo", [_], set: ^"bar")
    end

    assert_raise ArgumentError, ~r/malformed :set in update/, fn ->
      update("foo", [_], set: ^["bar"])
    end
  end

  test "keyword lists are expected" do
    assert_raise Ecto.Query.CompileError,
                 ~r"malformed update `\[1\]` in query expression", fn ->
      escape(quote do [1] end, [], __ENV__)
    end

    assert_raise Ecto.Query.CompileError,
                 ~r"malformed :set in update `\[1\]`, expected a keyword list", fn ->
      escape(quote do [set: [1]] end, [], __ENV__)
    end
  end

  test "update operations are validated" do
    assert_raise Ecto.Query.CompileError, "unknown key `:unknown` in update", fn ->
      escape(quote do [unknown: [1]] end, [], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, "unknown key `:unknown` in update", fn ->
      update("foo", [_], ^[unknown: [1]])
    end
  end
end
