defmodule Ecto.Query.Builder.LimitOffsetTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  test "overrides on duplicated limit and offset" do
    query = "posts" |> limit([], 1) |> limit([], 2)
    assert query.limit.expr == 2

    query = "posts" |> offset([], 1) |> offset([], 2) |> select([], 3)
    assert query.offset.expr == 2
  end
end
