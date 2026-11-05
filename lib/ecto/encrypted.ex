defmodule Ecto.Encrypted do
  @moduledoc """
  Defines a type that encrypts values before writing them to the database.

  Encryption uses Erlang's `:crypto` module directly and any AEAD cipher
  it supports, such as `:aes_256_gcm`, `:aes_128_gcm`, `:aes_256_ccm`,
  and `:chacha20_poly1305`.

  Each value is encrypted with its own key, derived with HMAC-SHA256
  from the configured key and a random salt.

  ## Usage

  First define a module that uses `Ecto.Encrypted` and implements the
  `c:keys/0` callback:

      defmodule MyApp.Encrypted do
        use Ecto.Encrypted

        @impl true
        def keys do
          [
            %{
              tag: "v1",
              cipher: :aes_256_gcm,
              key: Application.fetch_env!(:my_app, :encryption_key_v1)
            }
          ]
        end
      end

  Now use it as the type of a field:

      schema "users" do
        field :ssn, MyApp.Encrypted, redact: true
      end

  The column must be a binary one. In migrations, use `:binary`.

  Remember to pass `redact: true` to the field. Otherwise the
  decrypted value may show up when inspecting the struct, which
  includes logs and error reports.

  ## Keys

  `c:keys/0` returns a list of keys. Each key is a map with the
  following fields:

    * `:tag` - a binary of 1 to 255 bytes identifying the key
    * `:cipher` - an AEAD cipher supported by `:crypto`
    * `:key` - the key itself, as a binary

  Other fields are ignored.

  The first key in the list is used for encryption. All keys can be
  used for decryption. The tag is stored as a prefix of each encrypted
  value, so we know which key to use when decrypting. The cipher is
  never stored, so it can't be chosen by whoever writes to the database.

  Keys must be random and have the exact length required by the
  cipher, which is 32 bytes for all ciphers above except `:aes_128_gcm`.
  You can generate one with:

      $ elixir -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()'

  Then store it in an environment variable and read it in your
  `config/runtime.exs`:

      if config_env() == :prod do
        config :my_app,
          encryption_key_v1: Base.decode64!(System.fetch_env!("ENCRYPTION_KEY_V1"))
      end

  For development and test, you can set fixed keys in `config/dev.exs`
  and `config/test.exs` respectively. Use different keys per environment.
  Never store keys in module attributes, as they would then be written to
  `.beam` files.

  These keys are only for data stored in your database. Do not use
  or derive them from secrets shared with other parts of your system,
  such as Phoenix's `secret_key_base`. Those secrets may be rotated for
  reasons unrelated to your data, and doing so would make all of your
  encrypted data unreadable.

  ## Key and cipher rotation

  To rotate keys or change ciphers, add a new key with a new tag to
  the beginning of the list:

      def keys do
        [
          %{
            tag: "v2",
            cipher: :chacha20_poly1305,
            key: Application.fetch_env!(:my_app, :encryption_key_v2)
          },
          %{
            tag: "v1",
            cipher: :aes_256_gcm,
            key: Application.fetch_env!(:my_app, :encryption_key_v1)
          }
        ]
      end

  New values are encrypted with `"v2"` and existing values are still
  decrypted with `"v1"`. You can remove a key once all data encrypted
  with it has been re-encrypted.

  Loading and saving a struct again does not re-encrypt its data, as
  the decrypted value does not change. Use `Ecto.Changeset.force_change/3`
  to force the field to be written:

      user
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.force_change(:ssn, user.ssn)
      |> Repo.update!()

  ## Encoding

  By default, only binaries can be encrypted. You can encrypt other
  values by implementing the `c:encode/1` and `c:decode/1` callbacks,
  plus the `c:Ecto.Type.cast/1` callback to cast external input:

      defmodule MyApp.EncryptedMap do
        use Ecto.Encrypted

        @impl true
        defdelegate keys, to: MyApp.Encrypted

        @impl true
        def cast(value) when is_map(value), do: {:ok, value}
        def cast(_value), do: :error

        @impl true
        def encode(value), do: {:ok, JSON.encode!(value)}

        @impl true
        def decode(binary) do
          case JSON.decode(binary) do
            {:ok, value} -> {:ok, value}
            {:error, _} -> :error
          end
        end
      end

  The example above uses the `JSON` module from Elixir v1.18+. As with
  the `:map` type, keys are returned as strings after loading.

  ## Limitations

  Each value is encrypted with a random nonce, so encrypting the same
  value twice gives different results. This means you can't query
  encrypted fields: `where: u.ssn == ^ssn` will never match. If you need
  to look up encrypted values, store a hash of them in a separate
  column using `Ecto.HMAC`.

  Encrypted values are stored as raw binaries, so they can't be
  stored in fields of embedded schemas that are saved as JSON.

  ## Using outside of Ecto

  `use Ecto.Encrypted` also defines `encrypt/1` and `decrypt/1` in
  your module, which encrypt and decrypt binaries using its keys.
  These functions skip `c:encode/1` and `c:decode/1`.
  """

  @typedoc "A tag, an AEAD cipher supported by `:crypto`, and a key"
  @type key :: %{:tag => binary, :cipher => atom, :key => binary, optional(atom) => term}

  @doc """
  Returns the list of keys.

  The first key is used for encryption and all keys can be used for
  decryption.
  """
  @callback keys() :: [key, ...]

  @doc """
  Encodes a value into a binary to be encrypted.

  Defaults to accepting only binaries.
  """
  @callback encode(term) :: {:ok, binary} | :error

  @doc """
  Decodes a decrypted binary back into a value.

  Defaults to returning the binary as is.
  """
  @callback decode(binary) :: {:ok, term} | :error

  @auth_tag_size 16
  @salt_size 12

  @doc false
  defmacro __using__(_opts) do
    quote location: :keep do
      use Ecto.Type
      @behaviour Ecto.Encrypted

      @impl Ecto.Type
      def type, do: :binary

      @impl Ecto.Type
      def cast(value) when is_binary(value), do: {:ok, value}
      def cast(_value), do: :error

      @impl Ecto.Encrypted
      def encode(value) when is_binary(value), do: {:ok, value}
      def encode(_value), do: :error

      @impl Ecto.Encrypted
      def decode(binary), do: {:ok, binary}

      @impl Ecto.Type
      def dump(value) do
        with {:ok, binary} <- encode(value) do
          {:ok, encrypt(binary)}
        end
      end

      @impl Ecto.Type
      def load(value) when is_binary(value) do
        with {:ok, binary} <- decrypt(value) do
          decode(binary)
        end
      end

      def load(_value), do: :error

      # Do not store decrypted values in embeds
      @impl Ecto.Type
      def embed_as(_format), do: :dump

      @doc "Encrypts the given binary."
      def encrypt(binary), do: Ecto.Encrypted.encrypt(keys(), binary)

      @doc "Decrypts the given binary."
      def decrypt(binary), do: Ecto.Encrypted.decrypt(keys(), binary)

      defoverridable cast: 1, encode: 1, decode: 1
    end
  end

  @doc """
  Encrypts `plaintext` using the first key in `keys`.

  The value key is derived by computing `HMAC-SHA256(key, "Ecto.Encrypted" <> salt)`,
  truncated to the cipher's key length, where `salt` is 12 random bytes.
  The result has the format:

      <<byte_size(tag)::8, tag::binary, salt::binary-12, iv::binary,
        ciphertext::binary, auth_tag::binary-16>>

  The tag and its size are authenticated as additional data.

  Raises `ArgumentError` if the first key is invalid.
  """
  @spec encrypt([key, ...], binary) :: binary
  def encrypt([key | _], plaintext) when is_binary(plaintext) do
    {tag, cipher, key, key_length, iv_length} = validate_key!(key)
    aad = <<byte_size(tag), tag::binary>>

    <<salt::binary-size(@salt_size), iv::binary>> =
      :crypto.strong_rand_bytes(@salt_size + iv_length)

    value_key = derive_key(key, salt, key_length)

    {ciphertext, auth_tag} =
      :crypto.crypto_one_time_aead(cipher, value_key, iv, plaintext, aad, @auth_tag_size, true)

    aad <> salt <> iv <> ciphertext <> auth_tag
  end

  def encrypt(_keys, plaintext), do: raise_invalid_args!(plaintext, "plaintext")

  @doc """
  Decrypts `binary` using the key whose tag matches the one in `binary`.

  Returns `:error` if no key matches the tag or if the data has been
  tampered with. Raises `ArgumentError` if the matching key is invalid.
  """
  @spec decrypt([key, ...], binary) :: {:ok, binary} | :error
  def decrypt([_ | _] = keys, binary) when is_binary(binary) do
    with <<size, tag::binary-size(size), rest::binary>> <- binary,
         %{} = key <- Enum.find(keys, &match?(%{tag: ^tag}, &1)),
         {^tag, cipher, key, key_length, iv_length} = validate_key!(key),
         ciphertext_size = byte_size(rest) - @salt_size - iv_length - @auth_tag_size,
         true <- ciphertext_size >= 0,
         <<salt::binary-size(@salt_size), iv::binary-size(^iv_length),
           ciphertext::binary-size(^ciphertext_size), auth_tag::binary-size(@auth_tag_size)>> <-
           rest,
         aad = binary_part(binary, 0, size + 1),
         value_key = derive_key(key, salt, key_length),
         plaintext when is_binary(plaintext) <-
           :crypto.crypto_one_time_aead(cipher, value_key, iv, ciphertext, aad, auth_tag, false) do
      {:ok, plaintext}
    else
      _ -> :error
    end
  end

  def decrypt(_keys, binary), do: raise_invalid_args!(binary, "ciphertext")

  defp derive_key(key, salt, key_length) do
    <<value_key::binary-size(^key_length), _::binary>> =
      :crypto.mac(:hmac, :sha256, key, ["Ecto.Encrypted", salt])

    value_key
  end

  # Error messages must never include the keys themselves,
  # which is also why we avoid FunctionClauseError and MatchError
  defp raise_invalid_args!(data, name) when not is_binary(data) do
    raise ArgumentError, "expected #{name} to be a binary"
  end

  defp raise_invalid_args!(_data, _name) do
    raise ArgumentError, "expected Ecto.Encrypted keys to be a non-empty list of maps"
  end

  defp validate_key!(%{tag: tag, cipher: cipher, key: key})
       when is_binary(tag) and byte_size(tag) in 1..255 and is_atom(cipher) and is_binary(key) do
    info =
      try do
        :crypto.cipher_info(cipher)
      rescue
        ArgumentError ->
          raise ArgumentError,
                "unknown cipher #{inspect(cipher)} for Ecto.Encrypted key #{inspect(tag)}"
      end

    if not info.prop_aead do
      raise ArgumentError,
            "expected an AEAD cipher for Ecto.Encrypted key #{inspect(tag)}, " <>
              "got: #{inspect(cipher)}"
    end

    # Value keys are derived with HMAC-SHA256, which outputs 32 bytes
    if info.key_length > 32 do
      raise ArgumentError,
            "unsupported cipher #{inspect(cipher)} for Ecto.Encrypted key #{inspect(tag)}, " <>
              "keys longer than 32 bytes are not supported"
    end

    if byte_size(key) != info.key_length do
      raise ArgumentError,
            "expected Ecto.Encrypted key #{inspect(tag)} to have #{info.key_length} bytes " <>
              "for #{inspect(cipher)}, got: #{byte_size(key)} bytes"
    end

    {tag, cipher, key, info.key_length, info.iv_length}
  end

  defp validate_key!(_key) do
    raise ArgumentError,
          "expected each Ecto.Encrypted key to be a map with :tag (a binary of 1 to 255 bytes), " <>
            ":cipher (an atom), and :key (a binary)"
  end
end
