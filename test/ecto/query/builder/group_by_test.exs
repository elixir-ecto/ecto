defmodule Ecto.Query.Builder.GroupByTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.GroupBy
  doctest Ecto.Query.Builder.GroupBy

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
    message = "unbound variable `x` in query"
    assert_raise Ecto.Query.CompileError, message, fn ->
      escape(quote do x.y end, [], __ENV__)
    end

    message = "expected a field as an atom in `group_by`, got: `\"temp\"`"
    assert_raise ArgumentError, message, fn ->
      temp = "temp"
      group_by("posts", [p], [^temp])
    end

    message = "expected a list of fields in `group_by`, got: `\"temp\"`"
    assert_raise ArgumentError, message, fn ->
      temp = "temp"
      group_by("posts", [p], ^temp)
    end
  end

  test "group_by interpolation" do
    key = :title
    assert group_by("q", [q], ^key).group_bys == group_by("q", [q], [q.title]).group_bys
    assert group_by("q", [q], [^key]).group_bys == group_by("q", [q], [q.title]).group_bys
  end
end
