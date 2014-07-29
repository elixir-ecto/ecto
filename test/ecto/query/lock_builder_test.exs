defmodule Ecto.Query.LockBuilderTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  test "invalid lock" do
    assert_raise Ecto.QueryError, ~r"lock expression must be a boolean value or a string", fn ->
      %Ecto.Query{} |> lock(1) |> select([], 0)
    end
  end

  test "overrides on duplicated lock" do
    query = %Ecto.Query{} |> lock(false) |> lock(true)
    assert query.lock == true

  end
end
