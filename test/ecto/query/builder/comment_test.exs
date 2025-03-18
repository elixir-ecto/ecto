Code.require_file("../../../support/eval_helpers.exs", __DIR__)

defmodule Ecto.Query.Builder.CommentTest do
  use ExUnit.Case, async: true

  doctest Ecto.Query.Builder.Comment

  import Ecto.Query
  import Support.EvalHelpers

  test "raises on invalid comment" do
    assert_raise ArgumentError, "comment must not contain a closing */ character", fn ->
      quote_and_eval(%Ecto.Query{} |> comment("*/"))
    end
  end

  test "comment with string" do
    query = %Ecto.Query{} |> comment("FOO")
    assert query.comments == ["FOO"]
  end

  test "comment with atom" do
    query = "posts" |> comment(:foo)
    assert query.comments == ["foo"]
  end

  test "comment with variable" do
    assert_raise ArgumentError, fn ->
      quote_and_eval(%Ecto.Query{} |> comment(^"xxx"))
    end
  end
end
