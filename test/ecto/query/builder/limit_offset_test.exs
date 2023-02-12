Code.require_file "../../../support/eval_helpers.exs", __DIR__

defmodule Ecto.Query.Builder.LimitOffsetTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Support.EvalHelpers

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field :title
    end
  end

  test "overrides on duplicated limit and offset" do
    query = "posts" |> limit([], 1) |> limit([], 2)
    assert query.limit.expr == 2

    query = "posts" |> offset([], 1) |> offset([], 2) |> select([], 3)
    assert query.offset.expr == 2
  end

  test "with_ties" do
    # compile time query
    query = from(p in Post) |> limit([], 1) |> with_ties(true)
    assert query.limit.expr == 1
    assert query.limit.with_ties == true

    # runtime query
    query = "posts" |> limit([], 2) |> with_ties(^true)
    assert query.limit.expr == 2
    assert query.limit.with_ties == true
  end

  test "with_ties is removed when a new limit is set" do
    # compile time query
    query = from(p in Post) |> limit([], 1) |> with_ties(true) |> limit([], 2)
    assert query.limit.expr == 2
    assert query.limit.with_ties == false

    # runtime query
    query = "posts" |> limit([], 3) |> with_ties(true) |> limit([], 4)
    assert query.limit.expr == 4
    assert query.limit.with_ties == false
  end

  test "with_ties must be a runtime or compile time boolean" do
    msg = "`with_ties` expression must evaluate to a boolean at runtime, got: `1`"
    assert_raise RuntimeError, msg, fn ->
      with_ties("posts", ^1)
    end

    msg = "`with_ties` expression must be a compile time boolean or an interpolated value using ^, got: `1`"
    assert_raise Ecto.Query.CompileError, msg, fn ->
      quote_and_eval with_ties("posts", 1)
    end
  end

  test "with_ties requires a limit" do
    msg = "`with_ties` can only be applied to queries containing a `limit`"
    assert_raise Ecto.Query.CompileError, msg, fn ->
      with_ties("posts", true)
    end
  end
end
