defmodule Ecto.Query.Builder.JoinTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Join
  doctest Ecto.Query.Builder.Join

  import Ecto.Query

  test "invalid joins" do
    assert_raise ArgumentError,
                 ~r/invalid join qualifier `:whatever`/, fn ->
      qual = :whatever
      join("posts", qual, [p], c in "comments", true)
    end

    assert_raise ArgumentError,
                 "expected join to be a string, atom or {string, atom}, got: `123`", fn ->
      source = 123
      join("posts", :left, [p], c in ^source, true)
    end
  end

  defmacro join_macro(left, right) do
    quote do
      fragment("? <> ?", unquote(left), unquote(right))
    end
  end

  test "join with macros" do
    left = "left"
    right = "right"
    assert %{joins: [_]} = join("posts", :inner, [p], c in join_macro(^left, ^right), true)
  end

  test "join interpolation" do
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
  end

  test "invalid assoc/2 field" do
    assert_raise Ecto.Query.CompileError,
    ~r/you passed the variable \`field_var\` to \`assoc\/2\`/, fn ->
      escape({:assoc, nil, [{:join_var, nil, nil}, {:field_var, nil, nil}]}, nil, nil)
    end
  end

  test "interpolated values are ok for assoc/2 field" do
    escape({:assoc, nil, [{:join_var, nil, :context}, {:^, nil, [:interpolated_value]}]}, [join_var: true], nil)
  end
end
