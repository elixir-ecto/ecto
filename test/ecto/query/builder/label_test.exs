Code.require_file "../../../support/eval_helpers.exs", __DIR__

defmodule Ecto.Query.Builder.LabelTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Label
  doctest Ecto.Query.Builder.Label

  import Ecto.Query
  import Support.EvalHelpers

  test "label with literal string" do
    query = %Ecto.Query{} |> label("my-report")
    assert query.label == "my-report"
  end

  test "label via keyword syntax" do
    query = from p in "posts", label: "list-posts"
    assert query.label == "list-posts"
  end

  test "label with interpolated string" do
    report = "monthly-report"
    query = %Ecto.Query{} |> label(^report)
    assert query.label == "monthly-report"
  end

  test "overrides on duplicated label" do
    query = %Ecto.Query{} |> label("FOO") |> label("BAR")
    assert query.label == "BAR"
  end

  test "raises on non-string at compile time" do
    assert_raise Ecto.Query.CompileError, ~r"`1` is not a valid label", fn ->
      quote_and_eval(%Ecto.Query{} |> label(1))
    end
  end

  test "raises on literal containing */" do
    assert_raise Ecto.Query.CompileError, ~r"cannot contain `/\*`, `\*/`, or null bytes", fn ->
      quote_and_eval(%Ecto.Query{} |> label("evil */ DROP TABLE"))
    end
  end

  test "raises on literal containing /*" do
    assert_raise Ecto.Query.CompileError, ~r"cannot contain `/\*`, `\*/`, or null bytes", fn ->
      quote_and_eval(%Ecto.Query{} |> label("evil /* nested"))
    end
  end

  test "raises on literal containing a null byte" do
    assert_raise Ecto.Query.CompileError, ~r"cannot contain `/\*`, `\*/`, or null bytes", fn ->
      quote_and_eval(%Ecto.Query{} |> label("nul\0byte"))
    end
  end

  test "raises on interpolated value containing a null byte" do
    evil = "nul\0byte"

    assert_raise ArgumentError, ~r"cannot contain `/\*`, `\*/`, or null bytes", fn ->
      %Ecto.Query{} |> label(^evil)
    end
  end

  test "raises on interpolated value containing */" do
    evil = "evil */ DROP TABLE"

    assert_raise ArgumentError, ~r"cannot contain `/\*`, `\*/`, or null bytes", fn ->
      %Ecto.Query{} |> label(^evil)
    end
  end

  test "raises on interpolated value containing /*" do
    evil = "evil /* nested"

    assert_raise ArgumentError, ~r"cannot contain `/\*`, `\*/`, or null bytes", fn ->
      %Ecto.Query{} |> label(^evil)
    end
  end

  test "raises on interpolated non-string" do
    not_a_string = 123

    assert_raise ArgumentError, ~r"must be a string", fn ->
      %Ecto.Query{} |> label(^not_a_string)
    end
  end

  test "exclude resets the label" do
    query = %Ecto.Query{} |> label("FOO")
    assert Ecto.Query.exclude(query, :label).label == nil
  end
end
