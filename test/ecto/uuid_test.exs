defmodule Ecto.UUIDTest do
  use ExUnit.Case, async: true

  @test_uuid "601d74e4-a8d3-4b6e-8365-eddb4c893327"
  @test_uuid_upper_case "601D74E4-A8D3-4B6E-8365-EDDB4C893327"
  @test_uuid_invalid_characters "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  @test_uuid_invalid_shape "this is not UUID"
  @test_uuid_binary <<0x60, 0x1D, 0x74, 0xE4, 0xA8, 0xD3, 0x4B, 0x6E,
                      0x83, 0x65, 0xED, 0xDB, 0x4C, 0x89, 0x33, 0x27>>

  test "cast" do
    assert Ecto.UUID.cast(@test_uuid) == {:ok, @test_uuid}
    assert Ecto.UUID.cast(@test_uuid_upper_case) == {:ok, String.downcase(@test_uuid_upper_case)}
    assert Ecto.UUID.cast(@test_uuid_invalid_characters) == :error
    assert Ecto.UUID.cast(@test_uuid_invalid_shape) == :error
    assert Ecto.UUID.cast(@test_uuid_binary) == :error
    assert Ecto.UUID.cast(nil) == :error
  end

  test "cast!" do
    assert Ecto.UUID.cast!(@test_uuid) == @test_uuid
    assert_raise Ecto.CastError, "cannot cast <<96, 29, 116, 228, 168, 211, 75, 110, 131, 101, 237, 219, 76, 137, 51, 39>> to Ecto.UUID", fn ->
      assert Ecto.UUID.cast!(@test_uuid_binary)
    end
    assert_raise Ecto.CastError, "cannot cast nil to Ecto.UUID", fn ->
      assert Ecto.UUID.cast!(nil)
    end
  end

  test "load" do
    assert Ecto.UUID.load(@test_uuid_binary) == {:ok, @test_uuid}
    assert Ecto.UUID.load("") == :error
    assert_raise RuntimeError, ~r"trying to load string UUID as Ecto.UUID:", fn ->
      Ecto.UUID.load(@test_uuid)
    end
  end

  test "dump" do
    assert Ecto.UUID.dump(@test_uuid) == {:ok, @test_uuid_binary}
    assert Ecto.UUID.dump(@test_uuid_binary) == :error
  end

  test "generate" do
    assert << _::64, ?-, _::32, ?-, _::32, ?-, _::32, ?-, _::96 >> = Ecto.UUID.generate
  end
end
