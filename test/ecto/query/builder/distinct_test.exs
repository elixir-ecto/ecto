defmodule Ecto.Query.Builder.DistinctTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Distinct
  doctest Ecto.Query.Builder.Distinct

  import Ecto.Query

  test "escape" do
    assert {true, %{}} ==
           escape(true, [x: 0], __ENV__)

    assert {Macro.escape(quote do [asc: &0.y] end), %{}} ==
           escape(quote do x.y end, [x: 0], __ENV__)

    assert {Macro.escape(quote do [asc: &0.x, asc: &1.y] end), %{}} ==
           escape(quote do [x.x, y.y] end, [x: 0, y: 1], __ENV__)

    assert {Macro.escape(quote do [asc: &0.x, desc: &1.y] end), %{}} ==
           escape(quote do [x.x, desc: y.y] end, [x: 0, y: 1], __ENV__)

    import Kernel, except: [>: 2]
    assert {Macro.escape(quote do [asc: 1 > 2] end), %{}} ==
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

    message = "expected a list or keyword list of fields in `distinct`, got: `\"temp\"`"
    assert_raise ArgumentError, message, fn ->
      temp = "temp"
      distinct("posts", [p], ^temp)
    end
  end

  test "distinct interpolation" do
    key = :title
    assert distinct("q", [q], ^key).distinct == distinct("q", [q], [q.title]).distinct
    assert distinct("q", [q], [^key]).distinct == distinct("q", [q], [q.title]).distinct

    kw = [desc: :title]
    assert distinct("q", [q], ^kw).distinct == distinct("q", [q], [desc: q.title]).distinct

    bool = true
    assert distinct("q", [q], ^bool).distinct == distinct("q", [q], true).distinct
  end
end
