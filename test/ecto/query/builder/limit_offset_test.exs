defmodule Ecto.Query.Builder.LimitOffsetTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  test "overrides on duplicated limit and offset" do
    query = "posts" |> limit([], 1) |> limit([], 2)
    assert query.limit.expr == 2

    query = "posts" |> offset([], 1) |> offset([], 2) |> select([], 3)
    assert query.offset.expr == 2
  end

  test "with_ties" do
    # compile time 
    query = from(p in Post) |> limit([], 1) |> with_ties(true)
    assert query.limit.expr == 1
    assert query.limit.with_ties == true

    # run time
    query = from(p in Post) |> limit([], 2) |> with_ties(^true)
    assert query.limit.expr == 2
    assert query.limit.with_ties == true
  end

  test "with_ties is removed when a new limit is set" do
    # compile time 
    query = from(p in Post) |> limit([], 1) |> with_ties(true) |> limit([], 2)
    assert query.limit.expr == 2
    assert query.limit.with_ties == false

    # run time
    query = from(p in Post) |> limit([], 3) |> with_ties(^true) |> limit([], 4)
    assert query.limit.expr == 4
    assert query.limit.with_ties == false
  end

  test "with_ties requires a limit" do
    msg = "`with_ties` can only be applied to queries containing a `limit`"
    assert_raise Ecto.Query.CompileError, msg, fn ->
      with_ties("posts", true)
    end
  end
end
