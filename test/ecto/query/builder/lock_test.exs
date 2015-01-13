defmodule Ecto.Query.Builder.LockTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Lock
  doctest Ecto.Query.Builder.Lock

  import Ecto.Query

  test "lock interpolation" do
    lock = true
    assert lock("posts", ^lock).lock == true

    lock = "FOR UPDATE"
    assert lock("posts", ^lock).lock == "FOR UPDATE"
  end

  test "invalid lock" do
    assert_raise Ecto.Query.CompileError, ~r"invalid lock `1`", fn ->
      %Ecto.Query{} |> lock(^1) |> select([], 0)
    end
  end

  test "overrides on duplicated lock" do
    query = %Ecto.Query{} |> lock(false) |> lock(true)
    assert query.lock == true
  end
end
