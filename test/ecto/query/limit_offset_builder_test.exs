defmodule Ecto.Query.LimitOffsetBuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  test "invalid limit and offset" do
    assert_raise Ecto.QueryError, ~r"limit and offset expressions must be a single integer value", fn ->
      %Ecto.Query{} |> limit("a") |> select([], 0)
    end
  end

  test "overrides on duplicated limit and offset" do
    query = %Ecto.Query{} |> limit(1) |> limit(2)
    assert query.limit == 2

    query = %Ecto.Query{} |> offset(1) |> offset(2) |> select([], 3)
    assert query.offset == 2
  end
end
