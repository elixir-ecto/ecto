defmodule Ecto.Query.Builder.FilterTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Filter
  doctest Ecto.Query.Builder.Filter

  import Ecto.Query

  describe "escape" do
    test "handles expressions and params" do
      import Kernel, except: [==: 2, and: 2]

      assert escape(:where, quote do [] end, 0, [x: 0], __ENV__) ===
             {true, %{}}

      assert escape(:where, quote do [x: ^"foo"] end, 0, [x: 0], __ENV__) ===
             {Macro.escape(quote do &0.x == ^0 end), %{0 => {"foo", {0, :x}}}}

      assert escape(:where, quote do [x: ^"foo", y: ^"bar"] end, 0, [x: 0], __ENV__) ===
             {Macro.escape(quote do &0.x == ^0 and &0.y == ^1 end),
              %{0 => {"foo", {0, :x}}, 1 => {"bar", {0, :y}}}}

      assert escape(:where, quote do {x.x} == {^"foo"} end, 0, [x: 0], __ENV__) ===
             {Macro.escape(quote do {&0.x} == {^0} end),
              %{0 => {"foo", {0, :x}}}}
    end

    test "raises on invalid expressions" do
      assert_raise Ecto.Query.CompileError,
                   ~r"expected a keyword list at compile time in where, got: `\[\{1, 2\}\]`", fn ->
        escape(:where, quote do [{1, 2}] end, 0, [], __ENV__)
      end

      assert_raise Ecto.Query.CompileError,
                   ~r"Tuples can only be used in comparisons with literal tuples of the same size", fn ->
        escape(:where, quote do {1, 2} > ^foo end, 0, [], __ENV__)
      end
    end

    test "raises on nils" do
      assert_raise Ecto.Query.CompileError,
                   ~r"nil given for :x. Comparison with nil is forbidden as it is unsafe.", fn ->
        escape(:where, quote do [x: nil] end, 0, [], __ENV__)
      end
    end
  end

  describe "at runtime" do
    test "accepts empty keyword lists" do
      query = where(from(p in "posts"), [p], ^[])
      assert query.wheres == []
    end

    test "accepts keyword lists" do
      %{wheres: [where]} = where(from(p in "posts"), [p], ^[foo: 1, bar: "baz"])
      assert Macro.to_string(where.expr) ==
             "&0.foo() == ^0 and &0.bar() == ^1"
      assert where.params ==
             [{1, {0, :foo}}, {"baz", {0, :bar}}]
    end

    test "supports dynamic expressions" do
      dynamic = dynamic([p], p.foo == ^1 and p.bar == ^"baz")
      %{wheres: [where]} = where("posts", ^dynamic)
      assert Macro.to_string(where.expr) ==
             "&0.foo() == ^0 and &0.bar() == ^1"
      assert where.params ==
             [{1, {0, :foo}}, {"baz", {0, :bar}}]
    end

    test "raises on invalid keywords" do
      assert_raise ArgumentError, fn ->
        where(from(p in "posts"), [p], ^[{1, 2}])
      end
    end

    test "raises on nil" do
      assert_raise ArgumentError, fn ->
        where(from(p in "posts"), [p], ^[foo: nil])
      end
    end
  end
end
