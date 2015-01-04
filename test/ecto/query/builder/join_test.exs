defmodule Ecto.Query.Builder.JoinTest do
  use ExUnit.Case, async: true

  import Ecto.Query.Builder.Join
  doctest Ecto.Query.Builder.Join

  import Ecto.Query, only: [join: 5]

  test "invalid joins" do
    assert_raise Ecto.Query.CompileError,
                 ~r/invalid join qualifier `:whatever`/, fn ->
      qual = :whatever
      join("posts", qual, [p], c in "comments", true)
    end

    assert_raise Ecto.Query.CompileError,
                 "expected join to be a string or atom, got: `123`", fn ->
      source = 123
      join("posts", :left, [p], c in ^source, true)
    end
  end
end
