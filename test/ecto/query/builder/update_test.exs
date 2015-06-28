defmodule Ecto.Query.Builder.UpdateTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Update
  doctest Ecto.Query.Builder.Update

  test "escape" do
    assert {Macro.escape(quote do [set: [foo: &0.bar]] end), %{}} ==
           escape(quote do [set: [foo: x.bar]] end, [x: 0], __ENV__)
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
