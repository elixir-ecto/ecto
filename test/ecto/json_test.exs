defmodule Ecto.JsonTest do
  use ExUnit.Case, async: true

  defmodule User do
    use Ecto.Schema

    @derive Jason.Encoder
    schema "users" do
      has_many :comments, Ecto.Comment
    end
  end

  test "encodes decimal" do
    decimal = Decimal.new("1.0")
    assert Jason.encode!(decimal) == ~s("1.0")
  end

  test "fails on association not loaded" do
    assert_raise RuntimeError,
                 ~r/cannot encode association :comments from Ecto.JsonTest.User to JSON/,
                 fn -> Jason.encode!(%User{}.comments) end
  end

  test "fails when encoding __meta__" do
    assert_raise RuntimeError,
                 ~r/cannot encode metadata from the :__meta__ field for Ecto.JsonTest.User to JSON/,
                 fn -> Jason.encode!(%User{comments: []}) end
  end
end
