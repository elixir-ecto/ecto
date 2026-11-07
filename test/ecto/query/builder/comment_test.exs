Code.require_file "../../../support/eval_helpers.exs", __DIR__

defmodule Ecto.Query.Builder.CommentTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Comment
  doctest Ecto.Query.Builder.Comment

  import Ecto.Query
  import Support.EvalHelpers

  test "pre_comment with literal string" do
    query = %Ecto.Query{} |> pre_comment("list_posts")
    assert query.comments == [pre: "list_posts"]
  end

  test "post_comment with literal string" do
    query = %Ecto.Query{} |> post_comment("list_posts")
    assert query.comments == [post: "list_posts"]
  end

  test "pre_comment via keyword syntax" do
    query = from p in "posts", pre_comment: "list_posts"
    assert query.comments == [pre: "list_posts"]
  end

  test "comments accumulate in order" do
    query = %Ecto.Query{} |> pre_comment("a") |> post_comment("b") |> pre_comment("c")
    assert query.comments == [{:pre, "a"}, {:post, "b"}, {:pre, "c"}]
  end

  test "raises on interpolation (comments must be static)" do
    _report = "monthly"

    assert_raise Ecto.Query.CompileError, ~r"interpolation is not allowed", fn ->
      quote_and_eval(%Ecto.Query{} |> pre_comment(^_report))
    end
  end

  test "raises on a non-literal" do
    assert_raise Ecto.Query.CompileError, ~r"is not a valid comment", fn ->
      quote_and_eval(%Ecto.Query{} |> pre_comment(1))
    end
  end

  test "raises on a comment containing */" do
    assert_raise Ecto.Query.CompileError, ~r"cannot contain `/\*`, `\*/`, or null bytes", fn ->
      quote_and_eval(%Ecto.Query{} |> post_comment("evil */ DROP"))
    end
  end

  test "raises on a comment containing /*" do
    assert_raise Ecto.Query.CompileError, ~r"cannot contain `/\*`, `\*/`, or null bytes", fn ->
      quote_and_eval(%Ecto.Query{} |> pre_comment("evil /* nested"))
    end
  end

  # `/*!...*/` and `/*M!...*/` are executable comments and `/*+...*/` is an
  # optimizer hint on MySQL/MariaDB, so these prefixes must never be able to
  # land right after the opening `/*`.
  test "raises on a comment starting with ! (MySQL executable comment)" do
    assert_raise Ecto.Query.CompileError, ~r"cannot start with `!`, `\+`, or `M!`", fn ->
      quote_and_eval(%Ecto.Query{} |> pre_comment("!40000 DROP TABLE posts"))
    end
  end

  test "raises on a comment starting with + (MySQL optimizer hint)" do
    assert_raise Ecto.Query.CompileError, ~r"cannot start with `!`, `\+`, or `M!`", fn ->
      quote_and_eval(%Ecto.Query{} |> post_comment("+MAX_EXECUTION_TIME(1)"))
    end
  end

  test "raises on a comment starting with M! (MariaDB executable comment)" do
    assert_raise Ecto.Query.CompileError, ~r"cannot start with `!`, `\+`, or `M!`", fn ->
      quote_and_eval(%Ecto.Query{} |> pre_comment("M!100000 DROP TABLE posts"))
    end
  end

  test "exclude resets the comments" do
    query = %Ecto.Query{} |> pre_comment("a") |> post_comment("b")
    assert Ecto.Query.exclude(query, :comments).comments == []
  end
end
