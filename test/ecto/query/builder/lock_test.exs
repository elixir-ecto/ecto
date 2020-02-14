Code.require_file "../../../support/eval_helpers.exs", __DIR__

defmodule Ecto.Query.Builder.LockTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Lock
  doctest Ecto.Query.Builder.Lock

  import Ecto.Query
  import Support.EvalHelpers

  test "raises on invalid lock" do
    assert_raise Ecto.Query.CompileError, ~r"`1` is not a valid lock", fn ->
      quote_and_eval(%Ecto.Query{} |> lock(1))
    end
  end

  test "lock with string" do
    query = %Ecto.Query{} |> lock("FOO")
    assert query.lock == "FOO"
  end

  test "lock with fragment" do
    query = "posts" |> lock([p], fragment("update on ?", p))
    assert query.lock == {:fragment, [], [raw: "update on ", expr: {:&, [], [0]}, raw: ""]}
  end

  test "overrides on duplicated lock" do
    query = %Ecto.Query{} |> lock("FOO") |> lock("BAR")
    assert query.lock == "BAR"
  end
end
