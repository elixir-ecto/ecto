defmodule Ecto.Query.Builder.FilterTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Filter
  doctest Ecto.Query.Builder.Filter

  test "escape" do
    import Kernel, except: [==: 2, and: 2]

    assert escape(:where, quote do [] end, [x: 0], __ENV__) ===
           {true, %{}}

    assert escape(:where, quote do [x: ^"foo"] end, [x: 0], __ENV__) ===
           {Macro.escape(quote do &0.x == ^0 end), %{0 => {"foo", {0, :x}}}}

    assert escape(:where, quote do [x: ^"foo", y: ^"bar"] end, [x: 0], __ENV__) ===
           {Macro.escape(quote do &0.x == ^0 and &0.y == ^1 end),
            %{0 => {"foo", {0, :x}}, 1 => {"bar", {0, :y}}}}
  end

  test "runtime!" do
    assert runtime!(:where, []) |> Macro.to_string === "true"

    assert runtime!(:where, [x: "foo"]) |> Macro.to_string ===
           ~S|&0.x() == %Ecto.Query.Tagged{tag: nil, type: {0, :x}, value: "foo"}|

   assert runtime!(:where, [x: "foo", y: "bar"]) |> Macro.to_string ===
          ~S|&0.x() == %Ecto.Query.Tagged{tag: nil, type: {0, :x}, value: "foo"}| <>
            " and " <>
          ~S|&0.y() == %Ecto.Query.Tagged{tag: nil, type: {0, :y}, value: "bar"}|
  end

  test "invalid filter" do
    assert_raise Ecto.Query.CompileError,
                 ~r"expected a keyword list at compile time in where, got: `\[\{1, 2\}\]`", fn ->
      escape(:where, quote do [{1, 2}] end, [], __ENV__)
    end
  end

  test "invalid runtime filter" do
    assert_raise ArgumentError,
    ~r"expected a keyword list in where, got: `\[\{\"foo\", \"bar\"\}\]`", fn ->
      runtime!(:where, [{"foo", "bar"}])
    end
  end
end
