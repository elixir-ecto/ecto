Code.require_file "../../../support/eval_helpers.exs", __DIR__

defmodule Ecto.Query.Builder.PreloadTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  import Support.EvalHelpers

  import Ecto.Query.Builder.Preload
  doctest Ecto.Query.Builder.Preload

  test "invalid preload" do
    assert_raise Ecto.Query.CompileError, ~r"`1` is not a valid preload expression", fn ->
      quote_and_eval(%Ecto.Query{} |> preload(1))
    end
  end

  test "preload accumulates" do
    query = %Ecto.Query{} |> preload(:foo) |> preload(:bar)
    assert query.preloads == [:foo, :bar]
  end
end
