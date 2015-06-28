defmodule Ecto.Query.Builder.UpdateTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Ecto.Query.Builder.Update
  doctest Ecto.Query.Builder.Update

  test "escape" do
    assert {Macro.escape(quote do [set: [foo: &0.bar]] end), [], %{}} ==
           escape(quote do [set: [foo: x.bar]] end, [x: 0], __ENV__)
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
    [runtime, compile] = query.updates
    assert runtime.expr == [set: [foo: {:^, [], [0]}]]
    assert runtime.params == [{"foo", {0, :foo}}]
    assert compile.expr == [inc: [bar: {:^, [], [0]}]]
    assert compile.params == [{"bar", {0, :bar}}]
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
end
