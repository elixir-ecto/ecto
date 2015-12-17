defmodule Ecto.Query.Builder.DistinctTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Distinct
  doctest Ecto.Query.Builder.Distinct

  import Ecto.Query

  test "escape" do
    assert {Macro.escape(quote do [&0.y] end), %{}} ==
           escape(quote do x.y end, [x: 0], __ENV__)

    assert {Macro.escape(quote do [&0.x, &1.y] end), %{}} ==
           escape(quote do [x.x, y.y] end, [x: 0, y: 1], __ENV__)

    import Kernel, except: [>: 2]
    assert {Macro.escape(quote do [1 > 2] end), %{}} ==
           escape(quote do 1 > 2 end, [], __ENV__)
  end

  test "escape raise" do
    assert_raise Ecto.Query.CompileError, "unbound variable `x` in query", fn ->
      escape(quote do x.y end, [], __ENV__)
    end

    message = "expected a field as an atom in `distinct`, got: `\"temp\"`"
    assert_raise ArgumentError, message, fn ->
      temp = "temp"
      distinct("posts", [p], [^temp])
    end

    message = "expected a boolean or a list of fields in `distinct`, got: `\"temp\"`"
    assert_raise ArgumentError, message, fn ->
      temp = "temp"
      distinct("posts", [p], ^temp)
    end
  end

  test "distinct interpolation" do
    key = :title
    assert distinct("q", [q], ^key).distinct == distinct("q", [q], [q.title]).distinct
    assert distinct("q", [q], [^key]).distinct == distinct("q", [q], [q.title]).distinct

    bool = true
    assert distinct("q", [q], ^bool).distinct == distinct("q", [q], true).distinct
  end
end
