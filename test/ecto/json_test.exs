defmodule Ecto.JsonTest do
  use ExUnit.Case, async: true

  @implementations [{Jason, Jason.Encoder}, {JSON, JSON.Encoder}]

  loaded_implementations =
    for {_lib, encoder} = implementation <- @implementations,
        Code.ensure_loaded?(encoder),
        do: implementation

  defmodule User do
    use Ecto.Schema

    @derive Keyword.values(loaded_implementations)
    schema "users" do
      has_many :comments, Ecto.Comment
    end
  end

  for {json_library, _encoder} <- loaded_implementations do
    describe to_string(json_library) do
      test "encodes decimal" do
        decimal = Decimal.new("1.0")
        assert unquote(json_library).encode!(decimal) == ~s("1.0")
      end

      test "fails on association not loaded" do
        assert_raise RuntimeError,
                     ~r/cannot encode association :comments from Ecto.JsonTest.User to JSON/,
                     fn -> unquote(json_library).encode!(%User{}.comments) end
      end

      test "fails when encoding __meta__" do
        assert_raise RuntimeError,
                     ~r/cannot encode metadata from the :__meta__ field for Ecto.JsonTest.User to JSON/,
                     fn -> unquote(json_library).encode!(%User{comments: []}) end
      end
    end
  end
end
