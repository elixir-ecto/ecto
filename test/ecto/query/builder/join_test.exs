defmodule Ecto.Query.Builder.JoinTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Join
  doctest Ecto.Query.Builder.Join

  import Ecto.Query

  defmacro join_macro(left, right) do
    quote do
      fragment("? <> ?", unquote(left), unquote(right))
    end
  end

  test "expands macros as sources" do
    left = "left"
    right = "right"
    assert %{joins: [_]} = join("posts", :inner, [p], c in join_macro(^left, ^right), true)
  end

  test "accepts queries on interpolation" do
    qual = :left
    source = "comments"
    assert %{joins: [%{source: {"comments", nil}}]} =
            join("posts", qual, [p], c in ^source, true)

    qual = :right
    source = Comment
    assert %{joins: [%{source: {nil, Comment}}]} =
            join("posts", qual, [p], c in ^source, true)

    qual = :right
    source = {"user_comments", Comment}
    assert %{joins: [%{source: {"user_comments", Comment}}]} =
            join("posts", qual, [p], c in ^source, true)

    qual = :inner
    source = from c in "comments", where: c.public
    assert %{joins: [%{source: %Ecto.Query{from: {"comments", nil}}}]} =
            join("posts", qual, [p], c in ^source, true)
  end

  test "accepts interpolation on assoc/2 field" do
    assoc = :comments
    join("posts", :left, [p], c in assoc(p, ^assoc), true)
  end

  test "raises on invalid qualifier" do
    assert_raise ArgumentError,
                 ~r/invalid join qualifier `:whatever`/, fn ->
      qual = :whatever
      join("posts", qual, [p], c in "comments", true)
    end
  end

  test "raises on invalid interpolation" do
    assert_raise Protocol.UndefinedError, fn ->
      source = 123
      join("posts", :left, [p], c in ^source, true)
    end
  end

  test "raises on invalid assoc/2" do
    assert_raise Ecto.Query.CompileError,
                 ~r/you passed the variable \`field_var\` to \`assoc\/2\`/, fn ->
      escape(quote do assoc(join_var, field_var) end, nil, nil)
    end
  end
end
