defmodule Ecto.Query.Builder.FilterTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Filter
  doctest Ecto.Query.Builder.Filter

  test "escape" do
    import Kernel, except: [==: 2, and: 2]

    assert escape(:where, :and, quote do [] end, [x: 0], __ENV__) ===
           {true, %{}}

    assert escape(:where, :and, quote do [x: ^"foo"] end, [x: 0], __ENV__) ===
           {Macro.escape(quote do &0.x == ^0 end), %{0 => {"foo", {0, :x}}}}

    assert escape(:where, :and, quote do [x: ^"foo", y: ^"bar"] end, [x: 0], __ENV__) ===
           {Macro.escape(quote do &0.x == ^0 and &0.y == ^1 end),
            %{0 => {"foo", {0, :x}}, 1 => {"bar", {0, :y}}}}
  end

  test "runtime!" do
    assert runtime!(:where, [], :and) |> Macro.to_string ==
           "{true, []}"
    assert runtime!(:where, [x: 11], :and) |> Macro.to_string ==
           "{&0.x() == ^0, [{11, {0, :x}}]}"
    assert runtime!(:where, [x: 11, y: 13], :and) |> Macro.to_string ==
           "{&0.x() == ^0 and &0.y() == ^1, [{11, {0, :x}}, {13, {0, :y}}]}"
    assert runtime!(:where, [x: 11, y: 13], :or) |> Macro.to_string ==
           "{&0.x() == ^0 or &0.y() == ^1, [{11, {0, :x}}, {13, {0, :y}}]}"
  end

  test "invalid filter" do
    assert_raise Ecto.Query.CompileError,
                 ~r"expected a keyword list at compile time in where, got: `\[\{1, 2\}\]`", fn ->
      escape(:where, :and, quote do [{1, 2}] end, [], __ENV__)
    end
  end

  test "nil filter" do
    assert_raise Ecto.Query.CompileError,
                 ~r"nil given for :x. Comparison with nil is forbidden as it is unsafe.", fn ->
      escape(:where, :and, quote do [x: nil] end, [], __ENV__)
    end
  end

  test "invalid runtime filter" do
    assert_raise ArgumentError,
                 ~r"expected a keyword list in `where`, got: `\[\{\"foo\", \"bar\"\}\]`", fn ->
      runtime!(:where, [{"foo", "bar"}], :and)
    end
  end

  test "nil runtime filter" do
    assert_raise ArgumentError,
                 ~r"nil given for :x. Comparison with nil is forbidden as it is unsafe.", fn ->
      runtime!(:where, [x: nil], :and)
    end
  end
end
