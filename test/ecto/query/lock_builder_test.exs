defmodule Ecto.Query.LockBuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  test "invalid lock" do
    assert_raise Ecto.QueryError, ~r"lock expression must be a boolean value", fn ->
      Ecto.Query.Query[] |> lock("a") |> select([], 0)
    end
  end

  test "overrides on duplicated lock" do
    query = Ecto.Query.Query[] |> lock(false) |> lock(true)
    assert query.lock == true

  end
end
