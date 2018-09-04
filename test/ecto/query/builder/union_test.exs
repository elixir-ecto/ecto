defmodule Ecto.Query.Builder.UnionTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  test "adds union expressions" do
    union_query1 = from p in "posts1"
    union_query2 = from p in "posts2"
    query = "posts" |> union(union_query1) |> union_all(union_query2)

    assert {:union, ^union_query1} = query.unions |> Enum.at(0)
    assert {:union_all, ^union_query2} = query.unions |> Enum.at(1)
  end
end
