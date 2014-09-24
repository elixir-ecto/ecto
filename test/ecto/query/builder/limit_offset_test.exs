defmodule Ecto.Query.Builder.LimitOffsetTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  test "overrides on duplicated limit and offset" do
    %Ecto.Query{limit: %Ecto.Query.QueryExpr{expr: limit}} = %Ecto.Query{} |> limit([], 1) |> limit([], 2)
    assert limit == 2

    %Ecto.Query{offset: %Ecto.Query.QueryExpr{expr: offset}} = %Ecto.Query{} |> offset([], 1) |> offset([], 2) |> select([], 3)
    assert offset == 2
  end
end
