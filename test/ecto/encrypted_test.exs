defmodule Ecto.EncryptedTest do
  use ExUnit.Case, async: true

  @v1 %{tag: "v1", cipher: :aes_256_gcm, key: :binary.copy(<<1>>, 32)}
  @v2 %{tag: "v2", cipher: :chacha20_poly1305, key: :binary.copy(<<2>>, 32)}

  defmodule Encrypted do
    use Ecto.Encrypted
    def keys, do: [%{tag: "v1", cipher: :aes_256_gcm, key: :binary.copy(<<1>>, 32)}]
  end

  defmodule EncryptedTerm do
    use Ecto.Encrypted
    defdelegate keys, to: Encrypted
    def cast(value), do: {:ok, value}
    def encode(value), do: {:ok, :erlang.term_to_binary(value)}
    def decode(binary), do: {:ok, :erlang.binary_to_term(binary, [:safe])}
  end

  defmodule Schema do
    use Ecto.Schema

    schema "users" do
      field :ssn, Encrypted, redact: true
      field :data, EncryptedTerm, redact: true
    end
  end

  describe "encrypt/2 and decrypt/2" do
    for cipher <- [:aes_128_gcm, :aes_256_gcm, :aes_256_ccm, :chacha20_poly1305] do
      test "round-trips with #{cipher}" do
        cipher = unquote(cipher)
        key = :crypto.strong_rand_bytes(:crypto.cipher_info(cipher).key_length)
        keys = [%{tag: "tag", cipher: cipher, key: key}]
        ciphertext = Ecto.Encrypted.encrypt(keys, "secret")
        assert <<3, "tag", _::binary>> = ciphertext
        assert Ecto.Encrypted.decrypt(keys, ciphertext) == {:ok, "secret"}
      end
    end

    test "follows the documented format" do
      %{key: key} = @v1
      ciphertext = Ecto.Encrypted.encrypt([@v1], "secret")

      assert <<2, "v1", salt::binary-12, iv::binary-12, encrypted::binary-6, tag::binary-16>> =
               ciphertext

      <<value_key::binary-32>> = :crypto.mac(:hmac, :sha256, key, "Ecto.Encrypted" <> salt)

      assert :crypto.crypto_one_time_aead(
               :aes_256_gcm,
               value_key,
               iv,
               encrypted,
               <<2, "v1">>,
               tag,
               false
             ) == "secret"
    end

    test "derives shorter keys for aes_128_gcm" do
      keys = [%{tag: "v1", cipher: :aes_128_gcm, key: :binary.copy(<<1>>, 16)}]
      ciphertext = Ecto.Encrypted.encrypt(keys, "secret")

      assert <<2, "v1", salt::binary-12, iv::binary-12, encrypted::binary-6, tag::binary-16>> =
               ciphertext

      <<value_key::binary-16, _::binary>> =
        :crypto.mac(:hmac, :sha256, :binary.copy(<<1>>, 16), "Ecto.Encrypted" <> salt)

      assert :crypto.crypto_one_time_aead(
               :aes_128_gcm,
               value_key,
               iv,
               encrypted,
               <<2, "v1">>,
               tag,
               false
             ) == "secret"
    end

    test "uses random nonces" do
      assert Ecto.Encrypted.encrypt([@v1], "secret") != Ecto.Encrypted.encrypt([@v1], "secret")
    end

    test "decrypts with any key and encrypts with the first" do
      old = Ecto.Encrypted.encrypt([@v1], "secret")
      new = Ecto.Encrypted.encrypt([@v2, @v1], "secret")
      assert <<2, "v2", _::binary>> = new
      assert Ecto.Encrypted.decrypt([@v2, @v1], old) == {:ok, "secret"}
      assert Ecto.Encrypted.decrypt([@v2, @v1], new) == {:ok, "secret"}
    end

    test "fails on unknown tags" do
      ciphertext = Ecto.Encrypted.encrypt([@v1], "secret")
      assert Ecto.Encrypted.decrypt([@v2], ciphertext) == :error
    end

    test "fails when the tag is changed" do
      <<2, "v1", rest::binary>> = Ecto.Encrypted.encrypt([@v1], "secret")
      assert Ecto.Encrypted.decrypt([%{@v1 | tag: "v3"}], <<2, "v3", rest::binary>>) == :error
    end

    test "fails on tampered or malformed data" do
      ciphertext = Ecto.Encrypted.encrypt([@v1], "secret")
      size = byte_size(ciphertext) - 1
      <<head::binary-size(^size), last>> = ciphertext
      assert Ecto.Encrypted.decrypt([@v1], head <> <<Bitwise.bxor(last, 1)>>) == :error
      assert Ecto.Encrypted.decrypt([@v1], head) == :error
      assert Ecto.Encrypted.decrypt([@v1], <<2, "v1", 0>>) == :error
      assert Ecto.Encrypted.decrypt([@v1], <<>>) == :error
      assert Ecto.Encrypted.decrypt([@v1], <<9, "v1">>) == :error
    end
  end

  describe "key validation" do
    @secret :binary.copy("s", 16)
    @ciphertext <<2, "v1", 0::size(28)-unit(8)>>

    test "raises on invalid keys without leaking them" do
      for {keys, message} <- [
            {[], "non-empty list"},
            {%{tag: "v1", cipher: :aes_256_gcm, key: @secret}, "non-empty list"},
            {[%{tag: "v1", cipher: :unknown, key: @secret}], "unknown cipher :unknown"},
            {[%{tag: "v1", cipher: :aes_256_cbc, key: @secret}], "AEAD cipher"},
            {[%{tag: "v1", cipher: :aes_256_gcm, key: @secret}], "32 bytes"},
            {[%{tag: "v1", cipher: :aes_256_gcm}], "to be a map with"}
          ] do
        error = assert_raise ArgumentError, fn -> Ecto.Encrypted.encrypt(keys, "secret") end
        assert error.message =~ message
        refute error.message =~ @secret

        error = assert_raise ArgumentError, fn -> Ecto.Encrypted.decrypt(keys, @ciphertext) end
        assert error.message =~ message
        refute error.message =~ @secret
      end

      error =
        assert_raise ArgumentError, fn ->
          Ecto.Encrypted.encrypt([%{tag: "", cipher: :aes_256_gcm, key: @secret}], "secret")
        end

      assert error.message =~ "1 to 255 bytes"
    end

    test "only validates the key in use" do
      invalid = %{tag: "v2", cipher: :unknown, key: @secret}
      ciphertext = Ecto.Encrypted.encrypt([@v1, invalid], "secret")
      assert Ecto.Encrypted.decrypt([invalid, @v1], ciphertext) == {:ok, "secret"}
    end

    test "raises on non-binary data" do
      assert_raise ArgumentError, "expected plaintext to be a binary", fn ->
        Ecto.Encrypted.encrypt([@v1], Process.get(:not_a_binary, 123))
      end

      assert_raise ArgumentError, "expected ciphertext to be a binary", fn ->
        Ecto.Encrypted.decrypt([@v1], Process.get(:not_a_binary, 123))
      end
    end
  end

  describe "type" do
    test "dumps and loads" do
      assert {:ok, ciphertext} = Ecto.Type.dump(Encrypted, "secret")
      assert Ecto.Type.load(Encrypted, ciphertext) == {:ok, "secret"}
      assert Ecto.Type.load(Encrypted, "garbage") == :error
      assert Ecto.Type.dump(Encrypted, 123) == :error
      assert Ecto.Type.cast(Encrypted, 123) == :error
    end

    test "dumps and loads with custom encoding" do
      assert {:ok, ciphertext} = Ecto.Type.dump(EncryptedTerm, %{a: 1})
      assert Ecto.Type.load(EncryptedTerm, ciphertext) == {:ok, %{a: 1}}
    end

    test "dumps in embeds" do
      assert {:ok, ciphertext} = Ecto.Type.embedded_dump(Encrypted, "secret", :json)
      assert ciphertext != "secret"
      assert Ecto.Type.embedded_load(Encrypted, ciphertext, :json) == {:ok, "secret"}
    end

    test "works in schemas" do
      assert Schema.__schema__(:type, :ssn) == Encrypted
      refute inspect(%Schema{ssn: "secret"}) =~ "secret"
    end
  end
end
