defmodule Ecto.PoisonTest do
  use ExUnit.Case, async: true

  defmodule User do
    import Ecto.Schema, only: [schema: 2]

    schema "users" do
      has_many :comments, Ecto.Comment
    end
  end

  test "encodes decimal" do
    decimal = Decimal.new("1.0")
    assert Poison.encode!(decimal) == ~s("1.0")
  end

  test "fails on association not loaded" do
    assert_raise RuntimeError,
                 ~r/cannot encode association :comments from Ecto.PoisonTest.User to JSON/, fn ->
      Poison.encode!(%User{}.comments)
    end
  end

  test "fails when encoding __meta__" do
    assert_raise RuntimeError,
                 ~r/cannot encode metadata from the :__meta__ field for Ecto.PoisonTest.User to JSON/, fn ->
      Poison.encode!(%User{comments: []})
    end
  end
end
