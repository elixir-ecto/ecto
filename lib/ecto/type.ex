defmodule Ecto.Type do
  @moduledoc """
  Defines functions and the `Ecto.Type` behaviour for implementing
  basic custom types.

  Ecto provides two types of custom types: basic types and
  parameterized types. Basic types are simple, requiring only four
  callbacks to be implemented, and are enough for most occasions.
  Parameterized types can be customized on the field definition and
  provide a wide variety of callbacks.

  The definition of basic custom types and all of their callbacks are
  available in this module. You can learn more about parameterized
  types in `Ecto.ParameterizedType`. If in doubt, prefer to use
  basic custom types and rely on parameterized types if you need
  the extra functionality.

  ## External vs internal vs database representation

  The core functionality of a custom type is the mapping between
  external, internal and database representations of a value belonging
  to the type.

  For a definition of external and internal data take a look at the
  [related section](`Ecto.Changeset#module-external-vs-internal-data`)
  in the changeset documentation.

  ```mermaid
  stateDiagram-v2
    external: External Data
    internal: Internal Data
    database: Database Data
    external --> internal: cast/1
    external --> database: dump/1
    internal --> database: dump/1
    database --> internal: load/1
  ```

  ## Example

  Imagine you want to store a URI struct as part of a schema in a
  url-shortening service. There isn't an Ecto field type to support
  that value at runtime therefore a custom one is needed.

  You also want to query not only by the full url, but for example
  by specific ports used. This is possible by putting the URI data
  into a map field instead of just storing the plain
  string representation.

      from s in ShortUrl,
        where: fragment("?->>? ILIKE ?", s.original_url, "port", "443")

  So the custom type does need to handle the conversion from
  external data to runtime data (`c:cast/1`) as well as
  transforming that runtime data into the `:map` Ecto native type and
  back (`c:dump/1` and `c:load/1`).

      defmodule EctoURI do
        use Ecto.Type
        def type, do: :map

        # Provide custom casting rules.
        # Cast strings into the URI struct to be used at runtime
        def cast(uri) when is_binary(uri) do
          {:ok, URI.parse(uri)}
        end

        # Accept casting of URI structs as well
        def cast(%URI{} = uri), do: {:ok, uri}

        # Everything else is a failure though
        def cast(_), do: :error

        # When loading data from the database, as long as it's a map,
        # we just put the data back into a URI struct to be stored in
        # the loaded schema struct.
        def load(data) when is_map(data) do
          data =
            for {key, val} <- data do
              {String.to_existing_atom(key), val}
            end
          {:ok, struct!(URI, data)}
        end

        # When dumping data to the database, we *expect* a URI struct
        # but any value could be inserted into the schema struct at runtime,
        # so we need to guard against them.
        def dump(%URI{} = uri), do: {:ok, Map.from_struct(uri)}
        def dump(_), do: :error
      end

  Now we can use our new field type above in our schemas:

      defmodule ShortUrl do
        use Ecto.Schema

        schema "posts" do
          field :original_url, EctoURI
        end
      end

  Note: `nil` values are always bypassed and cannot be handled by
  custom types.

  > #### `use Ecto.Type` {: .info}
  >
  > When you `use Ecto.Type`, it will set `@behaviour Ecto.Type` and define
  > default, overridable implementations for `c:embed_as/1` and `c:equal?/2`.
  > You must implement your own `c:embed_as/1` function if you want
  > your `c:dump/1` to be called when exporting from Ecto.

  ## Custom types and primary keys

  Remember that, if you change the type of your primary keys,
  you will also need to change the type of all associations that
  point to said primary key.

  Imagine you want to encode the ID so they cannot enumerate the
  content in your application. An Ecto type could handle the conversion
  between the encoded version of the id and its representation in the
  database. For the sake of simplicity, we'll use base64 encoding in
  this example:

      defmodule EncodedId do
        use Ecto.Type

        def type, do: :id

        def cast(id) when is_integer(id) do
          {:ok, encode_id(id)}
        end
        def cast(_), do: :error

        def dump(id) when is_binary(id) do
          {:ok, id_decoded} = Base.decode64(id)
          {:ok, String.to_integer(id_decoded)}
        end

        def load(id) when is_integer(id) do
          {:ok, encode_id(id)}
        end

        defp encode_id(id) do
          id
          |> Integer.to_string()
          |> Base.encode64()
        end
      end

  To use it as the type for the id in our schema, we can use the
  `@primary_key` module attribute:

      defmodule BlogPost do
        use Ecto.Schema

        @primary_key {:id, EncodedId, autogenerate: true}
        schema "posts" do
          belongs_to :author, Author, type: EncodedId
          field :content, :string
        end
      end

      defmodule Author do
        use Ecto.Schema

        @primary_key {:id, EncodedId, autogenerate: true}
        schema "authors" do
          field :name, :string
          has_many :posts, BlogPost
        end
      end

  The `@primary_key` attribute will tell ecto which type to
  use for the id.

  Note the `type: EncodedId` option given to `belongs_to` in
  the `BlogPost` schema. By default, Ecto will treat
  associations as if their keys were `:integer`s. Our primary
  keys are a custom type, so when Ecto tries to cast those
  ids, it will fail.

  Alternatively, you can set `@foreign_key_type EncodedId`
  after `@primary_key` to automatically configure the type
  of all `belongs_to` fields.
  """

  import Kernel, except: [match?: 2]

  @doc false
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Ecto.Type
      def embed_as(_), do: :self
      def equal?(term1, term2), do: term1 == term2
      defoverridable embed_as: 1, equal?: 2
    end
  end

  @typedoc "An Ecto type, primitive or custom."
  @type t :: primitive | custom

  @typedoc "Primitive Ecto types (handled by Ecto)."
  @type primitive :: base | composite

  @typedoc "Custom types are represented by user-defined modules."
  @type custom :: module | {:parameterized, {module, term}}

  @type base ::
          :integer
          | :float
          | :boolean
          | :string
          | :bitstring
          | :map
          | :binary
          | :decimal
          | :id
          | :binary_id
          | :utc_datetime
          | :naive_datetime
          | :date
          | :time
          | :any
          | :utc_datetime_usec
          | :naive_datetime_usec
          | :time_usec
          | :duration

  @type composite :: {:array, t} | {:map, t} | private_composite

  @typep private_composite :: {:try, t} | {:in, t} | {:supertype, :datetime}

  @base ~w(
    integer float decimal boolean string bitstring map binary id binary_id any
    utc_datetime naive_datetime date time
    utc_datetime_usec naive_datetime_usec time_usec
    duration
  )a
  @composite ~w(array map try in param)a
  @variadic ~w(in splice)a

  @doc """
  Returns the underlying schema type for the custom type.

  For example, if you want to provide your own date
  structures, the type function should return `:date`.

  Note this function is not required to return Ecto primitive
  types, the type is only required to be known by the adapter.
  """
  @callback type :: t

  @doc """
  Casts the given input to the custom type.

  This callback is called on external input and can return any type,
  as long as the `dump/1` function is able to convert the returned
  value into an Ecto native type. There are two situations where
  this callback is called:

    1. When casting values by `Ecto.Changeset`
    2. When passing arguments to `Ecto.Query`

  You can return `:error` if the given term cannot be cast.
  A default error message of "is invalid" will be added to the
  changeset.

  You may also return `{:error, keyword()}` to customize the
  changeset error message and its metadata. Passing a `:message`
  key, will override the default message. It is not possible to
  override the `:type` key.

  For `{:array, CustomType}` or `{:map, CustomType}` the returned
  keyword list will be erased and the default error will be shown.
  """
  @callback cast(term) :: {:ok, term} | :error | {:error, keyword()}

  @doc """
  Loads the given term into a custom type.

  This callback is called when loading data from the database and
  receives an Ecto native type. It can return any type, as long as
  the `dump/1` function is able to convert the returned value back
  into an Ecto native type.
  """
  @callback load(term) :: {:ok, term} | :error

  @doc """
  Dumps the given term into an Ecto native type.

  This callback is called with any term that was stored in the struct
  and it needs to validate them and convert it to an Ecto native type.
  """
  @callback dump(term) :: {:ok, term} | :error

  @doc """
  Checks if two terms are semantically equal.

  This callback is used for determining equality of types in
  `Ecto.Changeset`.

  By default the terms are compared with the equal operator `==/2`.
  """
  @callback equal?(term, term) :: boolean

  @doc """
  Dictates how the type should be treated inside embeds.

  By default, the type is sent as itself, without calling
  dumping to keep the higher level representation. But
  it can be set to `:dump` so that it is dumped before
  being encoded.
  """
  @callback embed_as(format :: atom) :: :self | :dump

  @doc """
  Generates a loaded version of the data.

  This is callback is invoked when a custom type is given
  to `field` with the `:autogenerate` flag.
  """
  @callback autogenerate() :: term()

  @optional_callbacks autogenerate: 0

  ## Functions

  @doc """
  Checks if we have a primitive type.

      iex> primitive?(:string)
      true
      iex> primitive?(Another)
      false

      iex> primitive?({:array, :string})
      true
      iex> primitive?({:array, Another})
      true

  """
  @spec primitive?(t) :: boolean
  def primitive?({:parameterized, _}), do: true
  def primitive?({composite, _}) when composite in @composite, do: true
  def primitive?(base) when base in @base, do: true
  def primitive?(_), do: false

  @doc """
  Checks if the given type is parameterized by the given module.

      iex> type = Ecto.ParameterizedType.init(Ecto.Enum, values: [a: 1])
      iex> Ecto.Type.parameterized?(type, Ecto.Enum)
      true
      iex> Ecto.Type.parameterized?(type, MyEnum)
      false

  """
  @spec parameterized?(t, module) :: boolean
  def parameterized?({:parameterized, {module, _}}, module), do: true
  def parameterized?(_, _), do: false

  @doc """
  Checks if the given atom can be used as composite type.

      iex> composite?(:array)
      true
      iex> composite?(:string)
      false

  """
  @spec composite?(atom) :: boolean
  def composite?(atom), do: atom in @composite

  @doc """
  Checks if the given atom can be used as base type.

      iex> base?(:string)
      true
      iex> base?(:array)
      false
      iex> base?(Custom)
      false

  """
  @spec base?(atom) :: boolean
  def base?(atom), do: atom in @base

  @doc """
  Gets how the type is treated inside embeds for the given format.

  See `c:embed_as/1`.
  """
  def embed_as({:parameterized, {module, params}}, format), do: module.embed_as(format, params)
  def embed_as({composite, type}, format) when composite in @composite, do: embed_as(type, format)
  def embed_as(base, _format) when base in @base, do: :self
  def embed_as(mod, format), do: mod.embed_as(format)

  @doc """
  Dumps the `value` for `type` considering it will be embedded in `format`.

  ## Examples

      iex> Ecto.Type.embedded_dump(:decimal, Decimal.new("1"), :json)
      {:ok, Decimal.new("1")}

  """
  def embedded_dump(type, value, format) do
    case embed_as(type, format) do
      :self -> {:ok, value}
      :dump -> dump(type, value, &embedded_dump(&1, &2, format))
    end
  end

  @doc """
  Loads the `value` for `type` considering it was embedded in `format`.

  ## Examples

      iex> Ecto.Type.embedded_load(:decimal, "1", :json)
      {:ok, Decimal.new("1")}

  """
  def embedded_load(type, value, format) do
    case embed_as(type, format) do
      :self ->
        case cast(type, value) do
          {:ok, _} = ok -> ok
          _ -> :error
        end

      :dump ->
        load(type, value, &embedded_load(&1, &2, format))
    end
  end

  @doc """
  Retrieves the underlying schema type for the given, possibly custom, type.

      iex> type(:string)
      :string
      iex> type(Ecto.UUID)
      :uuid

      iex> type({:array, :string})
      {:array, :string}
      iex> type({:array, Ecto.UUID})
      {:array, :uuid}

      iex> type({:map, Ecto.UUID})
      {:map, :uuid}

  """
  @spec type(t) :: t
  def type(type)
  def type({:parameterized, {type, params}}), do: type.type(params)
  def type({:array, type}), do: {:array, type(type)}
  def type({:map, type}), do: {:map, type(type)}
  def type({:try, type}), do: type(type)
  def type(type) when type in @base, do: type
  def type(type) when is_atom(type), do: type.type()
  def type(type), do: type

  @doc """
  Checks if a given type matches with a primitive type
  that can be found in queries.

      iex> match?(:string, :any)
      true
      iex> match?(:any, :string)
      true
      iex> match?(:string, :string)
      true

      iex> match?({:array, :string}, {:array, :any})
      true

      iex> match?(Ecto.UUID, :uuid)
      true
      iex> match?(Ecto.UUID, :string)
      false

  """
  @spec match?(t, primitive) :: boolean
  def match?(schema_type, query_type) do
    if primitive?(schema_type) do
      do_match?(schema_type, query_type)
    else
      do_match?(schema_type.type(), query_type)
    end
  end

  defp do_match?(_left, :any), do: true
  defp do_match?(:any, _right), do: true
  defp do_match?({outer, left}, {outer, right}), do: match?(left, right)
  defp do_match?(:decimal, type) when type in [:float, :integer], do: true
  defp do_match?(:binary_id, :binary), do: true
  defp do_match?(:id, :integer), do: true
  defp do_match?(type, type), do: true
  defp do_match?(:naive_datetime, {:supertype, :datetime}), do: true
  defp do_match?(:naive_datetime_usec, {:supertype, :datetime}), do: true
  defp do_match?(:utc_datetime, {:supertype, :datetime}), do: true
  defp do_match?(:utc_datetime_usec, {:supertype, :datetime}), do: true
  defp do_match?(_, _), do: false

  @doc """
  Dumps a value to the given type.

  Opposite to casting, dumping requires the returned value
  to be a valid Ecto type, as it will be sent to the
  underlying data store.

      iex> dump(:string, nil)
      {:ok, nil}
      iex> dump(:string, "foo")
      {:ok, "foo"}

      iex> dump(:integer, 1)
      {:ok, 1}
      iex> dump(:integer, "10")
      :error

      iex> dump(:binary, "foo")
      {:ok, "foo"}
      iex> dump(:binary, 1)
      :error

      iex> dump({:array, :integer}, [1, 2, 3])
      {:ok, [1, 2, 3]}
      iex> dump({:array, :integer}, [1, "2", 3])
      :error
      iex> dump({:array, :binary}, ["1", "2", "3"])
      {:ok, ["1", "2", "3"]}

  """
  @spec dump(t, term) :: {:ok, term} | :error
  @spec dump(t, term, (t, term -> {:ok, term} | :error)) :: {:ok, term} | :error
  def dump(type, value, dumper \\ &dump/2)

  def dump({:parameterized, {module, params}}, value, dumper) do
    module.dump(value, dumper, params)
  end

  def dump(_type, nil, _dumper) do
    {:ok, nil}
  end

  def dump({:try, type}, value, dumper) do
    case dump(type, value, dumper) do
      {:ok, _} = ok -> ok
      :error -> {:ok, value}
    end
  end

  def dump({qual, type}, value, dumper) when qual in @variadic do
    case dump({:array, type}, value, dumper) do
      {:ok, value} -> {:ok, {qual, value}}
      :error -> :error
    end
  end

  def dump({:array, {:parameterized, _} = type}, value, dumper),
    do: array_with_type(value, type, dumper, false, [])

  def dump({:array, type}, value, dumper), do: array_with_type(value, type, dumper, true, [])
  def dump({:map, type}, value, dumper), do: map(value, type, dumper, false, %{})

  def dump(:any, value, _dumper), do: {:ok, value}
  def dump(:integer, value, _dumper), do: same_integer(value)
  def dump(:float, value, _dumper), do: dump_float(value)
  def dump(:boolean, value, _dumper), do: same_boolean(value)
  def dump(:map, value, _dumper), do: same_map(value)
  def dump(:string, value, _dumper), do: same_binary(value)
  def dump(:binary, value, _dumper), do: same_binary(value)
  def dump(:bitstring, value, _dumper), do: same_bitstring(value)
  def dump(:id, value, _dumper), do: same_integer(value)
  def dump(:binary_id, value, _dumper), do: same_binary(value)
  def dump(:decimal, value, _dumper), do: same_decimal(value)
  def dump(:date, value, _dumper), do: same_date(value)
  def dump(:time, value, _dumper), do: dump_time(value)
  def dump(:time_usec, value, _dumper), do: dump_time_usec(value)
  def dump(:naive_datetime, value, _dumper), do: dump_naive_datetime(value)
  def dump(:naive_datetime_usec, value, _dumper), do: dump_naive_datetime_usec(value)
  def dump(:utc_datetime, value, _dumper), do: dump_utc_datetime(value)
  def dump(:utc_datetime_usec, value, _dumper), do: dump_utc_datetime_usec(value)
  def dump(:duration, value, _dumper), do: same_duration(value)
  def dump({:supertype, :datetime}, value, _dumper), do: dump_any_datetime(value)
  def dump(mod, value, _dumper) when is_atom(mod), do: mod.dump(value)

  defp dump_float(term) when is_float(term), do: {:ok, term}
  defp dump_float(_), do: :error

  defp dump_time(%Time{} = term), do: {:ok, check_no_usec!(term, :time)}
  defp dump_time(_), do: :error

  defp dump_time_usec(%Time{} = term), do: {:ok, check_usec!(term, :time_usec)}
  defp dump_time_usec(_), do: :error

  defp dump_any_datetime(%NaiveDateTime{} = term), do: {:ok, term}
  defp dump_any_datetime(%DateTime{} = term), do: {:ok, term}
  defp dump_any_datetime(_), do: :error

  defp dump_naive_datetime(%NaiveDateTime{} = term),
    do: {:ok, check_no_usec!(term, :naive_datetime)}

  defp dump_naive_datetime(_), do: :error

  defp dump_naive_datetime_usec(%NaiveDateTime{} = term),
    do: {:ok, check_usec!(term, :naive_datetime_usec)}

  defp dump_naive_datetime_usec(_), do: :error

  defp dump_utc_datetime(%DateTime{} = datetime) do
    kind = :utc_datetime
    {:ok, datetime |> check_utc_timezone!(kind) |> check_no_usec!(kind)}
  end

  defp dump_utc_datetime(_), do: :error

  defp dump_utc_datetime_usec(%DateTime{} = datetime) do
    kind = :utc_datetime_usec
    {:ok, datetime |> check_utc_timezone!(kind) |> check_usec!(kind)}
  end

  defp dump_utc_datetime_usec(_), do: :error

  @doc """
  Loads a value with the given type.

      iex> load(:string, nil)
      {:ok, nil}
      iex> load(:string, "foo")
      {:ok, "foo"}

      iex> load(:integer, 1)
      {:ok, 1}
      iex> load(:integer, "10")
      :error

  """
  @spec load(t, term) :: {:ok, term} | :error
  @spec load(t, term, (t, term -> {:ok, term} | :error)) :: {:ok, term} | :error
  def load(type, value, loader \\ &load/2)

  def load({:parameterized, {module, params}}, value, loader) do
    module.load(value, loader, params)
  end

  def load(_type, nil, _loader) do
    {:ok, nil}
  end

  def load({:try, type}, value, loader) do
    case load(type, value, loader) do
      {:ok, _} = ok -> ok
      :error -> {:ok, value}
    end
  end

  def load({:array, {:parameterized, _} = type}, value, loader),
    do: array_with_type(value, type, loader, false, [])

  def load({:array, type}, value, loader), do: array_with_type(value, type, loader, true, [])
  def load({:map, type}, value, loader), do: map(value, type, loader, false, %{})

  def load(:any, value, _loader), do: {:ok, value}
  def load(:integer, value, _loader), do: same_integer(value)
  def load(:float, value, _loader), do: load_float(value)
  def load(:boolean, value, _loader), do: same_boolean(value)
  def load(:map, value, _loader), do: same_map(value)
  def load(:string, value, _loader), do: same_binary(value)
  def load(:binary, value, _loader), do: same_binary(value)
  def load(:bitstring, value, _loader), do: same_bitstring(value)
  def load(:id, value, _loader), do: same_integer(value)
  def load(:binary_id, value, _loader), do: same_binary(value)
  def load(:decimal, value, _loader), do: same_decimal(value)
  def load(:date, value, _loader), do: same_date(value)
  def load(:time, value, _loader), do: load_time(value)
  def load(:time_usec, value, _loader), do: load_time_usec(value)
  def load(:naive_datetime, value, _loader), do: load_naive_datetime(value)
  def load(:naive_datetime_usec, value, _loader), do: load_naive_datetime_usec(value)
  def load(:utc_datetime, value, _loader), do: load_utc_datetime(value)
  def load(:utc_datetime_usec, value, _loader), do: load_utc_datetime_usec(value)
  def load(:duration, value, _loader), do: same_duration(value)
  def load(mod, value, _loader), do: mod.load(value)

  defp load_float(term) when is_float(term), do: {:ok, term}
  defp load_float(term) when is_integer(term), do: {:ok, :erlang.float(term)}
  defp load_float(_), do: :error

  defp load_time(%Time{} = time), do: {:ok, truncate_usec(time)}
  defp load_time(_), do: :error

  defp load_time_usec(%Time{} = time), do: {:ok, pad_usec(time)}
  defp load_time_usec(_), do: :error

  # This is a downcast, which is always fine, and in case
  # we try to send a naive datetime where a datetime is expected,
  # the adapter will either explicitly error (Postgres) or it will
  # accept the data (MySQL), which is fine as we always assume UTC
  defp load_naive_datetime(%DateTime{} = datetime),
    do:
      {:ok,
       datetime |> check_utc_timezone!(:naive_datetime) |> DateTime.to_naive() |> truncate_usec()}

  defp load_naive_datetime(%NaiveDateTime{} = naive_datetime),
    do: {:ok, truncate_usec(naive_datetime)}

  defp load_naive_datetime(_), do: :error

  defp load_naive_datetime_usec(%DateTime{} = datetime),
    do:
      {:ok,
       datetime |> check_utc_timezone!(:naive_datetime_usec) |> DateTime.to_naive() |> pad_usec()}

  defp load_naive_datetime_usec(%NaiveDateTime{} = naive_datetime),
    do: {:ok, pad_usec(naive_datetime)}

  defp load_naive_datetime_usec(_), do: :error

  # This is an upcast but because we assume the database
  # is always in UTC, we can perform it.
  defp load_utc_datetime(%NaiveDateTime{} = naive_datetime),
    do: {:ok, naive_datetime |> truncate_usec() |> DateTime.from_naive!("Etc/UTC")}

  defp load_utc_datetime(%DateTime{} = datetime),
    do: {:ok, datetime |> check_utc_timezone!(:utc_datetime) |> truncate_usec()}

  defp load_utc_datetime(_),
    do: :error

  defp load_utc_datetime_usec(%NaiveDateTime{} = naive_datetime),
    do: {:ok, naive_datetime |> pad_usec() |> DateTime.from_naive!("Etc/UTC")}

  defp load_utc_datetime_usec(%DateTime{} = datetime),
    do: {:ok, datetime |> check_utc_timezone!(:utc_datetime_usec) |> pad_usec()}

  defp load_utc_datetime_usec(_),
    do: :error

  @doc """
  Casts a value to the given type.

  `cast/2` is used by the finder queries and changesets to cast outside values to
  specific types.

  Note that nil can be cast to all primitive types as data stores allow nil to be
  set on any column.

  NaN and infinite decimals are not supported, use custom types instead.

      iex> cast(:any, "whatever")
      {:ok, "whatever"}

      iex> cast(:any, nil)
      {:ok, nil}
      iex> cast(:string, nil)
      {:ok, nil}

      iex> cast(:integer, 1)
      {:ok, 1}
      iex> cast(:integer, "1")
      {:ok, 1}
      iex> cast(:integer, "1.0")
      :error

      iex> cast(:id, 1)
      {:ok, 1}
      iex> cast(:id, "1")
      {:ok, 1}
      iex> cast(:id, "1.0")
      :error

      iex> cast(:float, 1.0)
      {:ok, 1.0}
      iex> cast(:float, 1)
      {:ok, 1.0}
      iex> cast(:float, "1")
      {:ok, 1.0}
      iex> cast(:float, "1.0")
      {:ok, 1.0}
      iex> cast(:float, "1-foo")
      :error

      iex> cast(:boolean, true)
      {:ok, true}
      iex> cast(:boolean, false)
      {:ok, false}
      iex> cast(:boolean, "1")
      {:ok, true}
      iex> cast(:boolean, "0")
      {:ok, false}
      iex> cast(:boolean, "whatever")
      :error

      iex> cast(:string, "beef")
      {:ok, "beef"}
      iex> cast(:binary, "beef")
      {:ok, "beef"}

      iex> cast(:decimal, Decimal.new("1.0"))
      {:ok, Decimal.new("1.0")}
      iex> cast(:decimal, "1.0bad")
      :error

      iex> cast({:array, :integer}, [1, 2, 3])
      {:ok, [1, 2, 3]}
      iex> cast({:array, :integer}, ["1", "2", "3"])
      {:ok, [1, 2, 3]}
      iex> cast({:array, :string}, [1, 2, 3])
      :error
      iex> cast(:string, [1, 2, 3])
      :error

      iex> cast(:utc_datetime, "2014-04-17T14:00:00Z")
      {:ok, ~U[2014-04-17 14:00:00Z]}
      iex> cast(:utc_datetime, "2014-04-17T14:00:00.030Z")
      {:ok, ~U[2014-04-17 14:00:00Z]}
      iex> cast(:utc_datetime, "2014-04-17T12:00:00-02:00")
      {:ok, ~U[2014-04-17 14:00:00Z]}

  """
  @spec cast(t, term) :: {:ok, term} | {:error, keyword()} | :error
  def cast({:parameterized, {type, params}}, value), do: type.cast(value, params)
  def cast({:in, _type}, nil), do: :error
  def cast(_type, nil), do: {:ok, nil}

  def cast({:try, type}, value) do
    case cast(type, value) do
      {:ok, _} = ok -> ok
      _ -> {:ok, value}
    end
  end

  def cast(type, value) do
    cast_fun(type).(value)
  end

  defp cast_fun(:integer), do: &cast_integer/1
  defp cast_fun(:float), do: &cast_float/1
  defp cast_fun(:boolean), do: &cast_boolean/1
  defp cast_fun(:map), do: &cast_map/1
  defp cast_fun(:string), do: &cast_binary/1
  defp cast_fun(:binary), do: &cast_binary/1
  defp cast_fun(:bitstring), do: &cast_bitstring/1
  defp cast_fun(:id), do: &cast_integer/1
  defp cast_fun(:binary_id), do: &cast_binary/1
  defp cast_fun(:any), do: &{:ok, &1}
  defp cast_fun(:decimal), do: &cast_decimal/1
  defp cast_fun(:date), do: &cast_date/1
  defp cast_fun(:time), do: &maybe_truncate_usec(cast_time(&1))
  defp cast_fun(:time_usec), do: &maybe_pad_usec(cast_time(&1))
  defp cast_fun(:naive_datetime), do: &maybe_truncate_usec(cast_naive_datetime(&1))
  defp cast_fun(:naive_datetime_usec), do: &maybe_pad_usec(cast_naive_datetime(&1))
  defp cast_fun(:utc_datetime), do: &maybe_truncate_usec(cast_utc_datetime(&1))
  defp cast_fun(:utc_datetime_usec), do: &maybe_pad_usec(cast_utc_datetime(&1))
  defp cast_fun(:duration), do: &cast_duration/1
  defp cast_fun({:supertype, :datetime}), do: &cast_any_datetime(&1)
  defp cast_fun({:parameterized, {mod, params}}), do: &mod.cast(&1, params)
  defp cast_fun({qual, type}) when qual in @variadic, do: cast_fun({:array, type})

  defp cast_fun({:array, {:parameterized, _} = type}) do
    fun = cast_fun(type)
    &array_with_index(&1, fun, false, 0, [])
  end

  defp cast_fun({:array, type}) do
    fun = cast_fun(type)
    &array_with_index(&1, fun, true, 0, [])
  end

  defp cast_fun({:map, {:parameterized, _} = type}) do
    fun = cast_fun(type)
    &map(&1, fun, false, %{})
  end

  defp cast_fun({:map, type}) do
    fun = cast_fun(type)
    &map(&1, fun, true, %{})
  end

  defp cast_fun(mod) when is_atom(mod) do
    fn
      nil -> {:ok, nil}
      value -> mod.cast(value)
    end
  end

  # We check for the byte size to avoid creating unnecessary large integers
  # which would never map to a database key (u64 is 20 digits only).
  defp cast_integer(term) when is_binary(term) and byte_size(term) < 32 do
    case Integer.parse(term) do
      {integer, ""} -> {:ok, integer}
      _ -> :error
    end
  end

  defp cast_integer(term) when is_integer(term), do: {:ok, term}
  defp cast_integer(_), do: :error

  defp cast_float(term) when is_binary(term) do
    case Float.parse(term) do
      {float, ""} -> {:ok, float}
      _ -> :error
    end
  end

  defp cast_float(term) when is_float(term), do: {:ok, term}
  defp cast_float(term) when is_integer(term), do: {:ok, :erlang.float(term)}
  defp cast_float(_), do: :error

  defp cast_decimal(term) when is_binary(term) do
    case Decimal.parse(term) do
      {decimal, ""} -> check_decimal(decimal, false)
      {_, remainder} when is_binary(remainder) and byte_size(remainder) > 0 -> :error
      :error -> :error
    end
  end

  defp cast_decimal(term), do: same_decimal(term)

  defp cast_boolean(term) when term in ~w(true 1), do: {:ok, true}
  defp cast_boolean(term) when term in ~w(false 0), do: {:ok, false}
  defp cast_boolean(term) when is_boolean(term), do: {:ok, term}
  defp cast_boolean(_), do: :error

  defp cast_binary(term) when is_binary(term), do: {:ok, term}
  defp cast_binary(_), do: :error

  defp cast_bitstring(term) when is_bitstring(term), do: {:ok, term}
  defp cast_bitstring(_), do: :error

  defp cast_map(term) when is_map(term), do: {:ok, term}
  defp cast_map(_), do: :error

  if Code.ensure_loaded?(Duration) do
    defp cast_duration(%Duration{} = term), do: {:ok, term}
  end

  defp cast_duration(_), do: :error

  @doc """
  Casts a value to the given type or raises an error.

  See `cast/2` for more information.

  ## Examples

      iex> Ecto.Type.cast!(:integer, "1")
      1
      iex> Ecto.Type.cast!(:integer, 1)
      1
      iex> Ecto.Type.cast!(:integer, nil)
      nil

      iex> Ecto.Type.cast!(:integer, 1.0)
      ** (Ecto.CastError) cannot cast 1.0 to :integer
  """
  def cast!(type, value) do
    case Ecto.Type.cast(type, value) do
      {:ok, value} ->
        value

      :error ->
        raise Ecto.CastError, type: type, value: value

      {:error, metadata} ->
        raise Ecto.CastError, [type: type, value: value] ++ Keyword.take(metadata, [:message])
    end
  end

  ## Shared helpers

  @compile {:inline, same_integer: 1, same_boolean: 1, same_map: 1, same_decimal: 1, same_date: 1}
  defp same_integer(term) when is_integer(term), do: {:ok, term}
  defp same_integer(_), do: :error

  defp same_boolean(term) when is_boolean(term), do: {:ok, term}
  defp same_boolean(_), do: :error

  defp same_binary(term) when is_binary(term), do: {:ok, term}
  defp same_binary(_), do: :error

  defp same_bitstring(term) when is_bitstring(term), do: {:ok, term}
  defp same_bitstring(_), do: :error

  defp same_map(term) when is_map(term), do: {:ok, term}
  defp same_map(_), do: :error

  defp same_decimal(term) when is_integer(term), do: {:ok, Decimal.new(term)}
  defp same_decimal(term) when is_float(term), do: {:ok, Decimal.from_float(term)}
  defp same_decimal(%Decimal{} = term), do: check_decimal(term, true)
  defp same_decimal(_), do: :error

  defp same_date(%Date{} = term), do: {:ok, term}
  defp same_date(_), do: :error

  if Code.ensure_loaded?(Duration) do
    defp same_duration(%Duration{} = term), do: {:ok, term}
  end

  defp same_duration(_), do: :error

  @doc false
  def empty_trimmed?(value, :binary), do: value == ""
  def empty_trimmed?(value, _type), do: is_binary(value) and String.trim_leading(value) == ""

  ## Adapter related

  @doc false
  def adapter_autogenerate(adapter, type) do
    type
    |> type()
    |> adapter.autogenerate()
  end

  @doc false
  def adapter_load(adapter, type, value) do
    if of_base_type?(type, value) do
      {:ok, value}
    else
      process_loaders(adapter.loaders(type(type), type), {:ok, value}, adapter)
    end
  end

  defp process_loaders(_, :error, _adapter),
    do: :error

  defp process_loaders([fun | t], {:ok, value}, adapter) when is_function(fun),
    do: process_loaders(t, fun.(value), adapter)

  defp process_loaders([type | t], {:ok, value}, adapter),
    do: process_loaders(t, load(type, value, &adapter_load(adapter, &1, &2)), adapter)

  defp process_loaders([], {:ok, _} = acc, _adapter),
    do: acc

  @doc false
  def adapter_dump(adapter, type, value) do
    process_dumpers(adapter.dumpers(type(type), type), {:ok, value}, adapter)
  end

  defp process_dumpers(_, :error, _adapter),
    do: :error

  defp process_dumpers([fun | t], {:ok, value}, adapter) when is_function(fun),
    do: process_dumpers(t, fun.(value), adapter)

  defp process_dumpers([type | t], {:ok, value}, adapter),
    do: process_dumpers(t, dump(type, value, &adapter_dump(adapter, &1, &2)), adapter)

  defp process_dumpers([], {:ok, _} = acc, _adapter),
    do: acc

  ## Date

  defp cast_date(binary) when is_binary(binary) do
    case Date.from_iso8601(binary) do
      {:ok, _} = ok ->
        ok

      {:error, _} ->
        case NaiveDateTime.from_iso8601(binary) do
          {:ok, naive_datetime} -> {:ok, NaiveDateTime.to_date(naive_datetime)}
          {:error, _} -> :error
        end
    end
  end

  defp cast_date(%{"year" => empty, "month" => empty, "day" => empty}) when empty in ["", nil],
    do: {:ok, nil}

  defp cast_date(%{year: empty, month: empty, day: empty}) when empty in ["", nil],
    do: {:ok, nil}

  defp cast_date(%{"year" => year, "month" => month, "day" => day}),
    do: cast_date(to_i(year), to_i(month), to_i(day))

  defp cast_date(%{year: year, month: month, day: day}),
    do: cast_date(to_i(year), to_i(month), to_i(day))

  defp cast_date(_),
    do: :error

  defp cast_date(year, month, day)
       when is_integer(year) and is_integer(month) and is_integer(day) do
    case Date.new(year, month, day) do
      {:ok, _} = ok -> ok
      {:error, _} -> :error
    end
  end

  defp cast_date(_, _, _),
    do: :error

  ## Time

  defp cast_time(<<hour::2-bytes, ?:, minute::2-bytes>>),
    do: cast_time(to_i(hour), to_i(minute), 0, nil)

  defp cast_time(binary) when is_binary(binary) do
    case Time.from_iso8601(binary) do
      {:ok, _} = ok -> ok
      {:error, _} -> :error
    end
  end

  defp cast_time(%{"hour" => empty, "minute" => empty}) when empty in ["", nil],
    do: {:ok, nil}

  defp cast_time(%{hour: empty, minute: empty}) when empty in ["", nil],
    do: {:ok, nil}

  defp cast_time(%{"hour" => hour, "minute" => minute} = map),
    do:
      cast_time(
        to_i(hour),
        to_i(minute),
        to_i(Map.get(map, "second")),
        to_i(Map.get(map, "microsecond"))
      )

  defp cast_time(%{
         hour: hour,
         minute: minute,
         second: second,
         microsecond: {microsecond, precision}
       }),
       do: cast_time(to_i(hour), to_i(minute), to_i(second), {to_i(microsecond), to_i(precision)})

  defp cast_time(%{hour: hour, minute: minute} = map),
    do:
      cast_time(
        to_i(hour),
        to_i(minute),
        to_i(Map.get(map, :second)),
        to_i(Map.get(map, :microsecond))
      )

  defp cast_time(_),
    do: :error

  defp cast_time(hour, minute, sec, usec) when is_integer(usec) do
    cast_time(hour, minute, sec, {usec, 6})
  end

  defp cast_time(hour, minute, sec, nil) do
    cast_time(hour, minute, sec, {0, 0})
  end

  defp cast_time(hour, minute, sec, {usec, precision})
       when is_integer(hour) and is_integer(minute) and
              (is_integer(sec) or is_nil(sec)) and is_integer(usec) and is_integer(precision) do
    case Time.new(hour, minute, sec || 0, {usec, precision}) do
      {:ok, _} = ok -> ok
      {:error, _} -> :error
    end
  end

  defp cast_time(_, _, _, _) do
    :error
  end

  defp cast_any_datetime(%DateTime{} = datetime), do: cast_utc_datetime(datetime)
  defp cast_any_datetime(other), do: cast_naive_datetime(other)

  ## Naive datetime

  defp cast_naive_datetime("-" <> rest) do
    with {:ok, naive_datetime} <- cast_naive_datetime(rest) do
      {:ok, %{naive_datetime | year: naive_datetime.year * -1}}
    end
  end

  defp cast_naive_datetime(
         <<year::4-bytes, ?-, month::2-bytes, ?-, day::2-bytes, sep, hour::2-bytes, ?:,
           minute::2-bytes>>
       )
       when sep in [?\s, ?T] do
    case NaiveDateTime.new(to_i(year), to_i(month), to_i(day), to_i(hour), to_i(minute), 0) do
      {:ok, _} = ok -> ok
      _ -> :error
    end
  end

  defp cast_naive_datetime(binary) when is_binary(binary) do
    case NaiveDateTime.from_iso8601(binary) do
      {:ok, _} = ok -> ok
      {:error, _} -> :error
    end
  end

  defp cast_naive_datetime(%{
         "year" => empty,
         "month" => empty,
         "day" => empty,
         "hour" => empty,
         "minute" => empty
       })
       when empty in ["", nil],
       do: {:ok, nil}

  defp cast_naive_datetime(%{year: empty, month: empty, day: empty, hour: empty, minute: empty})
       when empty in ["", nil],
       do: {:ok, nil}

  defp cast_naive_datetime(%{} = map) do
    with {:ok, %Date{} = date} <- cast_date(map),
         {:ok, %Time{} = time} <- cast_time(map) do
      NaiveDateTime.new(date, time)
    else
      _ -> :error
    end
  end

  defp cast_naive_datetime(_) do
    :error
  end

  ## UTC datetime

  defp cast_utc_datetime("-" <> rest) do
    with {:ok, utc_datetime} <- cast_utc_datetime(rest) do
      {:ok, %{utc_datetime | year: utc_datetime.year * -1}}
    end
  end

  defp cast_utc_datetime(
         <<year::4-bytes, ?-, month::2-bytes, ?-, day::2-bytes, sep, hour::2-bytes, ?:,
           minute::2-bytes>>
       )
       when sep in [?\s, ?T] do
    case NaiveDateTime.new(to_i(year), to_i(month), to_i(day), to_i(hour), to_i(minute), 0) do
      {:ok, naive_datetime} -> {:ok, DateTime.from_naive!(naive_datetime, "Etc/UTC")}
      _ -> :error
    end
  end

  defp cast_utc_datetime(binary) when is_binary(binary) do
    case DateTime.from_iso8601(binary) do
      {:ok, datetime, _offset} ->
        {:ok, datetime}

      {:error, :missing_offset} ->
        case NaiveDateTime.from_iso8601(binary) do
          {:ok, naive_datetime} -> {:ok, DateTime.from_naive!(naive_datetime, "Etc/UTC")}
          {:error, _} -> :error
        end

      {:error, _} ->
        :error
    end
  end

  defp cast_utc_datetime(%DateTime{time_zone: "Etc/UTC"} = datetime), do: {:ok, datetime}

  defp cast_utc_datetime(%DateTime{} = datetime) do
    case datetime |> DateTime.to_unix(:microsecond) |> DateTime.from_unix(:microsecond) do
      {:ok, _} = ok -> ok
      {:error, _} -> :error
    end
  end

  defp cast_utc_datetime(value) do
    case cast_naive_datetime(value) do
      {:ok, %NaiveDateTime{} = naive_datetime} ->
        {:ok, DateTime.from_naive!(naive_datetime, "Etc/UTC")}

      {:ok, _} = ok ->
        ok

      :error ->
        :error
    end
  end

  @doc """
  Checks if two terms are equal.

  Depending on the given `type` performs a structural or semantical comparison.

  ## Examples

      iex> equal?(:integer, 1, 1)
      true
      iex> equal?(:decimal, Decimal.new("1"), Decimal.new("1.00"))
      true

  """
  @spec equal?(t, term, term) :: boolean
  def equal?(_, nil, nil), do: true

  def equal?(type, term1, term2) do
    if fun = equal_fun(type) do
      fun.(term1, term2)
    else
      term1 == term2
    end
  end

  @doc """
  Checks if `collection` includes a `term`.

  Depending on the given `type` performs a structural or semantical comparison.

  ## Examples

      iex> include?(:integer, 1, 1..3)
      true
      iex> include?(:decimal, Decimal.new("1"), [Decimal.new("1.00"), Decimal.new("2.00")])
      true

  """
  @spec include?(t, term, Enum.t()) :: boolean
  def include?(type, term, collection) do
    if fun = equal_fun(type) do
      Enum.any?(collection, &fun.(term, &1))
    else
      term in collection
    end
  end

  defp equal_fun(:decimal), do: &equal_decimal?/2
  defp equal_fun(t) when t in [:time, :time_usec], do: &equal_time?/2
  defp equal_fun(t) when t in [:utc_datetime, :utc_datetime_usec], do: &equal_utc_datetime?/2

  defp equal_fun(t) when t in [:naive_datetime, :naive_datetime_usec],
    do: &equal_naive_datetime?/2

  defp equal_fun(t) when t in @base, do: nil

  defp equal_fun({:array, type}) do
    if fun = equal_fun(type) do
      &equal_list?(fun, &1, &2)
    end
  end

  defp equal_fun({:map, type}) do
    if fun = equal_fun(type) do
      &equal_map?(fun, &1, &2)
    end
  end

  defp equal_fun({:parameterized, {mod, params}}) do
    &mod.equal?(&1, &2, params)
  end

  defp equal_fun(mod) when is_atom(mod), do: &mod.equal?/2

  defp equal_decimal?(%Decimal{} = a, %Decimal{} = b), do: Decimal.equal?(a, b)
  defp equal_decimal?(_, _), do: false

  defp equal_time?(%Time{} = a, %Time{} = b), do: Time.compare(a, b) == :eq
  defp equal_time?(_, _), do: false

  defp equal_utc_datetime?(%DateTime{} = a, %DateTime{} = b), do: DateTime.compare(a, b) == :eq
  defp equal_utc_datetime?(_, _), do: false

  defp equal_naive_datetime?(%NaiveDateTime{} = a, %NaiveDateTime{} = b),
    do: NaiveDateTime.compare(a, b) == :eq

  defp equal_naive_datetime?(_, _),
    do: false

  defp equal_list?(fun, [nil | xs], [nil | ys]), do: equal_list?(fun, xs, ys)
  defp equal_list?(fun, [x | xs], [y | ys]), do: fun.(x, y) and equal_list?(fun, xs, ys)
  defp equal_list?(_fun, [], []), do: true
  defp equal_list?(_fun, _, _), do: false

  defp equal_map?(_fun, map1, map2) when map_size(map1) != map_size(map2) do
    false
  end

  defp equal_map?(fun, %{} = map1, %{} = map2) do
    equal_map?(fun, Map.to_list(map1), map2)
  end

  defp equal_map?(fun, [{key, nil} | tail], other_map) do
    case other_map do
      %{^key => nil} -> equal_map?(fun, tail, other_map)
      _ -> false
    end
  end

  defp equal_map?(fun, [{key, val} | tail], other_map) do
    case other_map do
      %{^key => other_val} -> fun.(val, other_val) and equal_map?(fun, tail, other_map)
      _ -> false
    end
  end

  defp equal_map?(_fun, [], _) do
    true
  end

  defp equal_map?(_fun, _, _) do
    false
  end

  @doc """
  Format type for error messaging and logs.
  """
  def format({:parameterized, {type, params}}) do
    if function_exported?(type, :format, 1) do
      apply(type, :format, [params])
    else
      "##{inspect(type)}<#{inspect(params)}>"
    end
  end

  def format({composite, type}) when composite in [:array, :map, :in] do
    "{#{inspect(composite)}, #{format(type)}}"
  end

  def format(type), do: inspect(type)

  ## Helpers

  # Checks if a value is of the given primitive type.
  defp of_base_type?(:any, _), do: true
  defp of_base_type?(:id, term), do: is_integer(term)
  defp of_base_type?(:float, term), do: is_float(term)
  defp of_base_type?(:integer, term), do: is_integer(term)
  defp of_base_type?(:boolean, term), do: is_boolean(term)
  defp of_base_type?(:binary, term), do: is_binary(term)
  defp of_base_type?(:string, term), do: is_binary(term)
  defp of_base_type?(:map, term), do: is_map(term) and not Map.has_key?(term, :__struct__)
  defp of_base_type?(:decimal, value), do: Kernel.match?(%Decimal{}, value)
  defp of_base_type?(:date, value), do: Kernel.match?(%Date{}, value)
  defp of_base_type?(_, _), do: false

  defp array_with_index([nil | t], fun, true, index, acc) do
    array_with_index(t, fun, true, index + 1, [nil | acc])
  end

  defp array_with_index([h | t], fun, skip_nil?, index, acc) do
    case fun.(h) do
      {:ok, h} ->
        array_with_index(t, fun, skip_nil?, index + 1, [h | acc])

      :error ->
        :error

      {:error, custom_errors} ->
        {:error, Keyword.update(custom_errors, :source, [index], &[index | &1])}
    end
  end

  defp array_with_index([], _fun, _skip_nil?, _index, acc) do
    {:ok, Enum.reverse(acc)}
  end

  defp array_with_index(%_{} = struct, fun, skip_nil?, index, acc) do
    case Enumerable.impl_for(struct) do
      nil -> :error
      _ -> struct |> Enum.to_list() |> array_with_index(fun, skip_nil?, index, acc)
    end
  end

  defp array_with_index(_, _, _, _, _) do
    :error
  end

  defp map(map, fun, skip_nil?, acc) when is_map(map) do
    map_each(Map.to_list(map), fun, skip_nil?, acc)
  end

  defp map(_, _, _, _) do
    :error
  end

  defp map_each([{key, nil} | t], fun, true, acc) do
    map_each(t, fun, true, Map.put(acc, key, nil))
  end

  defp map_each([{key, value} | t], fun, skip_nil?, acc) do
    case fun.(value) do
      {:ok, value} ->
        map_each(t, fun, skip_nil?, Map.put(acc, key, value))

      :error ->
        :error

      {:error, custom_errors} ->
        {:error, Keyword.update(custom_errors, :source, [key], &[key | &1])}
    end
  end

  defp map_each([], _fun, _skip_nil?, acc) do
    {:ok, acc}
  end

  defp array_with_type([nil | t], type, fun, true, acc) do
    array_with_type(t, type, fun, true, [nil | acc])
  end

  defp array_with_type([h | t], type, fun, skip_nil?, acc) do
    case fun.(type, h) do
      {:ok, h} -> array_with_type(t, type, fun, skip_nil?, [h | acc])
      :error -> :error
    end
  end

  defp array_with_type([], _type, _fun, _skip_nil?, acc) do
    {:ok, Enum.reverse(acc)}
  end

  defp array_with_type(_, _, _, _, _) do
    :error
  end

  defp map(map, type, fun, skip_nil?, acc) when is_map(map) do
    map_each(Map.to_list(map), type, fun, skip_nil?, acc)
  end

  defp map(_, _, _, _, _) do
    :error
  end

  defp map_each([{key, value} | t], type, fun, skip_nil?, acc) do
    case fun.(type, value) do
      {:ok, value} -> map_each(t, type, fun, skip_nil?, Map.put(acc, key, value))
      :error -> :error
    end
  end

  defp map_each([], _type, _fun, _skip_nil?, acc) do
    {:ok, acc}
  end

  defp to_i(bin) when is_binary(bin) and byte_size(bin) < 32 do
    case Integer.parse(bin) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp to_i(int) when is_integer(int), do: int
  defp to_i(_), do: nil

  defp maybe_truncate_usec({:ok, struct}), do: {:ok, truncate_usec(struct)}
  defp maybe_truncate_usec(:error), do: :error

  defp maybe_pad_usec({:ok, struct}), do: {:ok, pad_usec(struct)}
  defp maybe_pad_usec(:error), do: :error

  defp truncate_usec(nil), do: nil
  defp truncate_usec(%{microsecond: {0, 0}} = struct), do: struct
  defp truncate_usec(struct), do: %{struct | microsecond: {0, 0}}

  defp pad_usec(nil), do: nil
  defp pad_usec(%{microsecond: {_, 6}} = struct), do: struct

  defp pad_usec(%{microsecond: {microsecond, _}} = struct),
    do: %{struct | microsecond: {microsecond, 6}}

  defp check_utc_timezone!(%{time_zone: "Etc/UTC"} = datetime, _kind), do: datetime

  defp check_utc_timezone!(datetime, kind) do
    raise ArgumentError,
          "#{inspect(kind)} expects the time zone to be \"Etc/UTC\", got `#{inspect(datetime)}`"
  end

  defp check_usec!(%{microsecond: {_, 6}} = datetime, _kind), do: datetime

  defp check_usec!(datetime, kind) do
    raise ArgumentError,
          "#{inspect(kind)} expects microsecond precision, got: #{inspect(datetime)}"
  end

  defp check_no_usec!(%{microsecond: {0, 0}} = datetime, _kind), do: datetime

  defp check_no_usec!(%struct{} = datetime, kind) do
    raise ArgumentError, """
    #{inspect(kind)} expects microseconds to be empty, got: #{inspect(datetime)}

    Use `#{inspect(struct)}.truncate(#{kind}, :second)` (available in Elixir v1.6+) to remove microseconds.
    """
  end

  defp check_decimal(%Decimal{coef: coef} = decimal, _) when is_integer(coef), do: {:ok, decimal}
  defp check_decimal(_decimal, false), do: :error

  defp check_decimal(decimal, true) do
    raise ArgumentError, """
    #{inspect(decimal)} is not allowed for type :decimal

    `+Infinity`, `-Infinity`, and `NaN` values are not supported, even though the `Decimal` library handles them. \
    To support them, you can create a custom type.
    """
  end
end
