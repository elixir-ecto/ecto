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
end
