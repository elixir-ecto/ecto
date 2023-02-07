Code.require_file "../../../support/eval_helpers.exs", __DIR__

defmodule Ecto.Query.Builder.LimitOffsetTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Support.EvalHelpers

  test "overrides on duplicated limit and offset" do
    query = "posts" |> limit([], 1) |> limit([], 2)
    assert query.limit.expr == 2

    query = "posts" |> offset([], 1) |> offset([], 2) |> select([], 3)
    assert query.offset.expr == 2
  end

  test "does not allow query variables in limit and offset" do
    assert_raise Ecto.Query.CompileError, "query variables are not allowed in limit expression", fn ->
      quote_and_eval from p in "posts", limit: p.x + 1
    end

    assert_raise Ecto.Query.CompileError, "query variables are not allowed in offset expression", fn ->
      quote_and_eval from p in "posts", offset: p.x + 2
    end
  end
end
