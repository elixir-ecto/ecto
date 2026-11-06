defmodule Ecto.HMACTest do
  use ExUnit.Case, async: true

  @key :binary.copy(<<1>>, 32)

  defmodule Lookup do
    use Ecto.HMAC
    def key, do: %{algorithm: :sha256, key: :binary.copy(<<1>>, 32)}
  end

  defmodule NormalizedLookup do
    use Ecto.HMAC
    defdelegate key, to: Lookup
    def encode(value) when is_binary(value), do: {:ok, String.downcase(value)}
    def encode(_), do: :error
  end

  test "hash/2" do
    assert Ecto.HMAC.hash(%{algorithm: :sha256, key: @key}, "value") ==
             :crypto.mac(:hmac, :sha256, @key, "Ecto.HMACvalue")

    assert Lookup.hash("value") == Ecto.HMAC.hash(%{algorithm: :sha256, key: @key}, "value")
  end

  test "raises on invalid keys without leaking them" do
    secret = :binary.copy("s", 16)

    for {key, message} <- [
          {secret, "to be a map"},
          {%{algorithm: :unknown, key: @key}, "unknown algorithm :unknown"},
          {%{algorithm: :sha256, key: secret}, "at least 32 bytes"}
        ] do
      error = assert_raise ArgumentError, fn -> Ecto.HMAC.hash(key, "value") end
      assert error.message =~ message
      refute error.message =~ secret
    end
  end

  test "prunes keys from the stacktrace on crypto errors" do
    # Extendable-output functions, such as :shake128, cannot be used with HMAC.
    # Depending on the OTP version, they fail in :crypto.hash_info/1 or :crypto.mac/4
    error =
      try do
        Ecto.HMAC.hash(%{algorithm: :shake128, key: @key}, "value")
      rescue
        e -> {e, __STACKTRACE__}
      end

    assert {exception, stacktrace} = error
    assert is_exception(exception)
    refute inspect(stacktrace) =~ inspect(@key)
  end

  test "dumps deterministically and loads as is" do
    assert {:ok, hash} = Ecto.Type.dump(Lookup, "value")
    assert Ecto.Type.dump(Lookup, "value") == {:ok, hash}
    assert hash == Lookup.hash("value")
    assert Ecto.Type.load(Lookup, hash) == {:ok, hash}
    assert Ecto.Type.dump(Lookup, 123) == :error
  end

  test "normalizes through encode/1" do
    assert Ecto.Type.dump(NormalizedLookup, "VALUE") == {:ok, Lookup.hash("value")}
  end

  test "dumps in embeds" do
    assert Ecto.Type.embedded_dump(Lookup, "value", :json) == {:ok, Lookup.hash("value")}
  end
end
