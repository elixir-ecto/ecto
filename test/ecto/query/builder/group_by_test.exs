defmodule Ecto.Query.Builder.GroupByTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.GroupBy
  doctest Ecto.Query.Builder.GroupBy

  import Ecto.Query

  describe "escape" do
    test "handles expressions and params" do
      assert {Macro.escape(quote do [&0.y()] end), {[], :acc}} ==
             escape(:group_by, quote do x.y() end, {[], :acc}, [x: 0], __ENV__)

      assert {Macro.escape(quote do [&0.x(), &1.y()] end), {[], :acc}} ==
             escape(:group_by, quote do [x.x(), y.y()] end, {[], :acc}, [x: 0, y: 1], __ENV__)

      import Kernel, except: [>: 2]
      assert {Macro.escape(quote do [1 > 2] end), {[], :acc}} ==
             escape(:group_by, quote do 1 > 2 end, {[], :acc}, [], __ENV__)
    end

    test "raises on unbound variables" do
      message = ~r"unbound variable `x` in query"
      assert_raise Ecto.Query.CompileError, message, fn ->
        escape(:group_by, quote do x.y end, {[], :acc}, [], __ENV__)
      end
    end
  end

  describe "at runtime" do
    test "accepts a field or a list of fields" do
      key = :title
      assert group_by("q", [q], ^key).group_bys == group_by("q", [q], [q.title]).group_bys
      assert group_by("q", [q], [^key]).group_bys == group_by("q", [q], [q.title]).group_bys
    end

    test "accepts dynamics" do
      key = dynamic([p], p.title)
      assert group_by("q", [q], ^key).group_bys == group_by("q", [q], [q.title]).group_bys
      assert group_by("q", [q], ^[key]).group_bys == group_by("q", [q], [q.title]).group_bys
    end

    test "raises when no a field or a list of fields" do
      message = "expected a field as an atom in `group_by`, got: `\"temp\"`"
      assert_raise ArgumentError, message, fn ->
        temp = "temp"
        group_by("posts", [p], [^temp])
      end

      message = "expected a list of fields and dynamics in `group_by`, got: `\"temp\"`"
      assert_raise ArgumentError, message, fn ->
        temp = "temp"
        group_by("posts", [p], ^temp)
      end
    end
  end
end
