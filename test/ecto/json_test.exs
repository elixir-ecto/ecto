defmodule Ecto.JsonTest do
  use ExUnit.Case, async: true

  defmodule User do
    use Ecto.Schema

    @derive Jason.Encoder
    schema "users" do
      has_many :comments, Ecto.Comment
    end
  end

  for json <- [Poison, Jason] do
    @json json

    test "#{@json}: encodes decimal" do
      decimal = Decimal.new("1.0")
      assert @json.encode!(decimal) == ~s("1.0")
    end

    test "#{@json}:fails on association not loaded" do
      assert_raise RuntimeError,
                   ~r/cannot encode association :comments from Ecto.JsonTest.User to JSON/, fn ->
        @json.encode!(%User{}.comments)
      end
    end

    test "#{@json}: fails when encoding __meta__" do
      assert_raise RuntimeError,
                   ~r/cannot encode metadata from the :__meta__ field for Ecto.JsonTest.User to JSON/, fn ->
        @json.encode!(%User{comments: []})
      end
    end
  end
end
