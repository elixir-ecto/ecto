defmodule Ecto.UUIDTest do
  use ExUnit.Case, async: true

  @test_uuid "601d74e4-a8d3-4b6e-8365-eddb4c893327"
  @test_uuid_binary <<0x60, 0x1D, 0x74, 0xE4, 0xA8, 0xD3, 0x4B, 0x6E,
                      0x83, 0x65, 0xED, 0xDB, 0x4C, 0x89, 0x33, 0x27>>

  test "cast" do
    assert Ecto.UUID.cast(@test_uuid) == {:ok, @test_uuid}
    assert Ecto.UUID.cast(@test_uuid_binary) == :error
    assert Ecto.UUID.cast(nil) == :error
  end

  test "load" do
    assert Ecto.UUID.load(@test_uuid_binary) == {:ok, @test_uuid}
    assert Ecto.UUID.load("") == :error
    assert_raise RuntimeError, ~r"trying to load string UUID as Ecto.UUID:", fn ->
      Ecto.UUID.load(@test_uuid)
    end
  end

  test "dump" do
    assert Ecto.UUID.dump(@test_uuid) == {:ok, %Ecto.Query.Tagged{value: @test_uuid_binary, type: :uuid}}
    assert Ecto.UUID.dump(@test_uuid_binary) == :error
  end

  test "generate" do
    assert << _::64, ?-, _::32, ?-, _::32, ?-, _::32, ?-, _::96 >> = Ecto.UUID.generate
  end
end
