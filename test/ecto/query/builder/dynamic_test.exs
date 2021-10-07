defmodule Ecto.Query.Builder.DynamicTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Dynamic
  doctest Ecto.Query.Builder.Dynamic

  import Ecto.Query

  defp query do
    from p in "posts", join: c in "comments", as: :comments, on: p.id == c.post_id
  end

  describe "fully_expand/2" do
    test "without params" do
      dynamic = dynamic([p], p.foo == true)
      assert {expr, _, params, [], _, _} = fully_expand(query(), dynamic)
      assert expr ==
             {:==, [], [{{:., [], [{:&, [], [0]}, :foo]}, [], []},
                        %Ecto.Query.Tagged{tag: nil, value: true, type: {0, :foo}}]}
      assert params == []
    end

    test "with params" do
      dynamic = dynamic([p], p.foo == ^1)
      assert {expr, _, params, [], _, _} = fully_expand(query(), dynamic)
      assert Macro.to_string(expr) == "&0.foo() == ^0"
      assert params == [{1, {0, :foo}}]
    end

    # TODO: AST is represented as string differently on versions pre 1.13
    if Version.match?(System.version(), ">= 1.13.0-dev") do
      test "with dynamic interpolation" do
        dynamic = dynamic([p], p.bar == ^2)
        dynamic = dynamic([p], p.foo == ^1 and ^dynamic or p.baz == ^3)
        assert {expr, _, params, [], _, _} = fully_expand(query(), dynamic)
        assert Macro.to_string(expr) ==
               "(&0.foo() == ^0 and &0.bar() == ^1) or &0.baz() == ^2"
        assert params == [{1, {0, :foo}}, {2, {0, :bar}}, {3, {0, :baz}}]
      end
    else
      test "with dynamic interpolation" do
        dynamic = dynamic([p], p.bar == ^2)
        dynamic = dynamic([p], p.foo == ^1 and ^dynamic or p.baz == ^3)
        assert {expr, _, params, [], _, _} = fully_expand(query(), dynamic)
        assert Macro.to_string(expr) ==
               "&0.foo() == ^0 and &0.bar() == ^1 or &0.baz() == ^2"
        assert params == [{1, {0, :foo}}, {2, {0, :bar}}, {3, {0, :baz}}]
      end
    end

    test "with subquery and dynamic interpolation" do
      dynamic = dynamic([p], p.sq in subquery(query()))
      dynamic = dynamic([p], p.bar1 == ^"bar1" or ^dynamic or p.bar3 == ^"bar3")
      dynamic = dynamic([p], p.foo == ^"foo" and ^dynamic and p.baz == ^"baz")
      assert {expr, binding, params, [_subquery], _, _} = fully_expand(query(), dynamic)
      assert Macro.to_string(binding) == "[p]"
      assert Macro.to_string(expr) ==
             "&0.foo() == ^0 and (&0.bar1() == ^1 or &0.sq() in {:subquery, 0} or &0.bar3() == ^3) and &0.baz() == ^4"
      assert params == [{"foo", {0, :foo}}, {"bar1", {0, :bar1}}, {:subquery, 0},
                        {"bar3", {0, :bar3}}, {"baz", {0, :baz}}]
    end
    
    test "with nested dynamic interpolation" do
      dynamic = dynamic([p], p.bar2 == ^"bar2")
      dynamic = dynamic([p], p.bar1 == ^"bar1" or ^dynamic or p.bar3 == ^"bar3")
      dynamic = dynamic([p], p.foo == ^"foo" and ^dynamic and p.baz == ^"baz")
      assert {expr, binding, params, [], _, _} = fully_expand(query(), dynamic)
      assert Macro.to_string(binding) == "[p]"
      assert Macro.to_string(expr) ==
             "&0.foo() == ^0 and (&0.bar1() == ^1 or &0.bar2() == ^2 or &0.bar3() == ^3) and &0.baz() == ^4"
      assert params == [{"foo", {0, :foo}}, {"bar1", {0, :bar1}}, {"bar2", {0, :bar2}},
                        {"bar3", {0, :bar3}}, {"baz", {0, :baz}}]
    end

    test "with multiple bindings" do
      dynamic = dynamic([a, b], a.bar == b.bar)
      dynamic = dynamic([p], p.foo == ^"foo" and ^dynamic and p.baz == ^"baz")
      assert {expr, binding, params, [], _, _} = fully_expand(query(), dynamic)
      assert Macro.to_string(binding) == "[a, b]"
      assert Macro.to_string(expr) ==
             "&0.foo() == ^0 and &0.bar() == &1.bar() and &0.baz() == ^1"
      assert params == [{"foo", {0, :foo}}, {"baz", {0, :baz}}]
    end

    test "with ... bindings" do
      dynamic = dynamic([..., c], c.bar == ^"bar")
      dynamic = dynamic([p], p.foo == ^"foo" and ^dynamic and p.baz == ^"baz")
      assert {expr, _, params, [], _, _} = fully_expand(query(), dynamic)
      assert Macro.to_string(expr) ==
             "&0.foo() == ^0 and &1.bar() == ^1 and &0.baz() == ^2"
      assert params == [{"foo", {0, :foo}}, {"bar", {1, :bar}}, {"baz", {0, :baz}}]
    end

    test "with join bindings" do
      dynamic = dynamic([comments: c], c.bar == ^"bar")
      assert {expr, _, params, [], _, _} = fully_expand(query(), dynamic)
      assert Macro.to_string(expr) == "&1.bar() == ^0"
      assert params ==  [{"bar", {1, :bar}}]
    end
  end
end
