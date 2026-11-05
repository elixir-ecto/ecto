defmodule Ecto.HMAC do
  @moduledoc """
  Defines a type that stores the HMAC of a value, allowing encrypted
  values to be looked up.

  Values encrypted with `Ecto.Encrypted` can't be queried, as encrypting
  the same value twice gives different results. To look them up, store
  the HMAC of the value in a separate column, often called a blind index.
  The HMAC of a given value is always the same, so it can be queried and
  have unique indexes.

  ## Usage

  First define a module that uses `Ecto.HMAC` and implements the
  `c:key/0` callback:

      defmodule MyApp.Lookup do
        use Ecto.HMAC

        @impl true
        def key do
          %{algorithm: :sha256, key: Application.fetch_env!(:my_app, :hmac_key)}
        end
      end

  Then add two fields to your schema, one encrypted and one hashed:

      schema "users" do
        field :email, MyApp.Encrypted, redact: true
        field :email_lookup, MyApp.Lookup, redact: true
      end

  Both columns must be binary ones. In migrations, use `:binary`.

  Both fields must be kept in sync in your changesets:

      def changeset(user, attrs) do
        user
        |> cast(attrs, [:email])
        |> put_email_lookup()
      end

      defp put_email_lookup(changeset) do
        case fetch_change(changeset, :email) do
          {:ok, email} -> put_change(changeset, :email_lookup, email)
          :error -> changeset
        end
      end

  Now you can query by the hashed field. Values are hashed whenever
  they are dumped, which includes query parameters:

      Repo.get_by(User, email_lookup: "jose@example.com")

  The hashed field holds the original value until the struct is saved.
  After that, and when loaded from the database, it holds the HMAC.

  ## Key

  `c:key/0` returns a map with the following fields:

    * `:algorithm` - the hash algorithm given to `:crypto.mac/4`,
      such as `:sha256`, `:sha512`, and `:sha3_256`
    * `:key` - the key itself, as a binary

  Other fields are ignored.

  The key must be random and must not be the same as any key used by
  `Ecto.Encrypted`. It must have at least as many bytes as the hash
  output, which is 32 bytes for `:sha256` and `:sha3_256` and 64 bytes
  for `:sha512`. You can generate one with:

      $ elixir -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()'

  Then store it in an environment variable and read it in your
  `config/runtime.exs`:

      if config_env() == :prod do
        config :my_app,
          hmac_key: Base.decode64!(System.fetch_env!("HMAC_KEY"))
      end

  For development and test, you can set fixed keys in `config/dev.exs`
  and `config/test.exs` respectively. Use different keys per environment.

  `c:key/0` is called every time a value is dumped, so it must be cheap.
  That's why the example above decodes the key once, when the
  configuration is loaded, instead of on every call. Never store the
  key in a module attribute, as it would then be written to `.beam` files.

  Unlike `Ecto.Encrypted`, there is a single key. Lookups can only use
  one key at a time, so changing the key or the algorithm requires
  computing all hashes again, by decrypting the encrypted column, before
  lookups will work.

  ## Normalization

  You may want lookups to ignore certain differences, such as case in
  emails. To do so, implement `c:encode/1`, which returns the binary
  to be hashed:

      @impl true
      def encode(email) when is_binary(email), do: {:ok, String.downcase(email)}
      def encode(_), do: :error

  As `c:encode/1` is called both when writing and when querying, both
  are always normalized in the same way. The encrypted field still
  stores the original value.

  ## Security

  The HMAC reveals which rows have the same value and how often each
  value appears. Only hash fields you need to look up.

  The HMAC protects values only while its key is secret. Once the key
  leaks, values with few possibilities, such as phone numbers, can be
  found by hashing all possibilities. So store the key separately from
  the database, as you would with encryption keys.

  ## Using outside of Ecto

  `use Ecto.HMAC` also defines `hash/1` in your module, which returns
  the HMAC of the given binary. It skips `c:encode/1`.
  """

  @typedoc "A hash algorithm supported by `:crypto.mac/4` and a key"
  @type key :: %{:algorithm => atom, :key => binary, optional(atom) => term}

  @doc """
  Returns the hash algorithm and the key.
  """
  @callback key() :: key

  @doc """
  Encodes a value into the binary to be hashed.

  Defaults to accepting only binaries.
  """
  @callback encode(term) :: {:ok, binary} | :error

  @doc false
  defmacro __using__(_opts) do
    quote location: :keep do
      use Ecto.Type
      @behaviour Ecto.HMAC

      @impl Ecto.Type
      def type, do: :binary

      @impl Ecto.Type
      def cast(value) when is_binary(value), do: {:ok, value}
      def cast(_value), do: :error

      @impl Ecto.HMAC
      def encode(value) when is_binary(value), do: {:ok, value}
      def encode(_value), do: :error

      @impl Ecto.Type
      def dump(value) do
        with {:ok, binary} <- encode(value) do
          {:ok, hash(binary)}
        end
      end

      @impl Ecto.Type
      def load(value) when is_binary(value), do: {:ok, value}
      def load(_value), do: :error

      # Do not store original values in embeds
      @impl Ecto.Type
      def embed_as(_format), do: :dump

      @doc "Returns the HMAC of the given binary."
      def hash(binary), do: Ecto.HMAC.hash(key(), binary)

      defoverridable cast: 1, encode: 1
    end
  end

  @doc """
  Returns the HMAC of `binary` with the given algorithm and key.

  The result is `HMAC(algorithm, key, "Ecto.HMAC" <> binary)`. The prefix
  ensures the result never matches HMACs computed elsewhere with the same
  key, such as the keys derived by `Ecto.Encrypted`.

  Raises `ArgumentError` if `key` is invalid.
  """
  @spec hash(key, binary) :: binary
  def hash(%{algorithm: algorithm, key: key}, binary)
      when is_atom(algorithm) and is_binary(key) and is_binary(binary) do
    size =
      try do
        :crypto.hash_info(algorithm).size
      rescue
        ArgumentError ->
          raise ArgumentError, "unknown algorithm #{inspect(algorithm)} for Ecto.HMAC key"
      end

    # RFC 2104 recommends keys of at least the size of the hash output
    if byte_size(key) < size do
      raise ArgumentError,
            "expected Ecto.HMAC key to have at least #{size} bytes " <>
              "for #{inspect(algorithm)}, got: #{byte_size(key)} bytes"
    end

    try do
      :crypto.mac(:hmac, algorithm, key, ["Ecto.HMAC", binary])
    rescue
      # Extendable-output functions, such as :shake128, have no fixed size
      # and cannot be used with HMAC. We rescue instead of checking the size
      # upfront because OpenSSL versions differ in the size they report
      ErlangError ->
        raise ArgumentError,
              "unsupported algorithm #{inspect(algorithm)} for Ecto.HMAC key, " <>
                "the algorithm must have a fixed output size"
    end
  end

  # Error messages must never include the key itself
  def hash(_key, binary) when is_binary(binary) do
    raise ArgumentError,
          "expected Ecto.HMAC key to be a map with :algorithm (an atom) and :key (a binary)"
  end

  def hash(_key, _binary), do: raise(ArgumentError, "expected value to hash to be a binary")
end
