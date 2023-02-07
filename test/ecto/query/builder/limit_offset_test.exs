defmodule Ecto.Query.Builder.LimitOffsetTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  test "overrides on duplicated limit and offset" do
    query = "posts" |> limit([], 1) |> limit([], 2)
    assert query.limit.expr == 2

    query = "posts" |> offset([], 1) |> offset([], 2) |> select([], 3)
    assert query.offset.expr == 2
  end

  test "does not allow column names in limit and offset" do
    assert_raise Ecto.Query.CompileError, "query variables are not allowed in limit expression", fn ->
      quoted = quote do: from p in "posts", limit: p.x + 1
      Code.eval_quoted(quoted, [], __ENV__)
    end

    assert_raise Ecto.Query.CompileError, "query variables are not allowed in offset expression", fn ->
      quoted = quote do: from p in "posts", offset: p.x + 2
      Code.eval_quoted(quoted, [], __ENV__)
    end
  end
end
