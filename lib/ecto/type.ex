defmodule Ecto.Type do
  @moduledoc """
  Defines functions and the `Ecto.Type` behaviour for implementing
  custom types.

  A custom type expects 4 functions to be implemented, all documented
  and described below. We also provide two examples of how custom
  types can be used in Ecto to augment existing types or providing
  your own types.

  Note: `nil` values are always bypassed and cannot be handled by
  custom types.

  ## Example

  Imagine you want to store an URI struct as part of a schema in an
  url-shortening service. There isn't an Ecto field type to support
  that value at runtime, therefore a custom one is needed.

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
        # we just put the data back into an URI struct to be stored in
        # the loaded schema struct.
        def load(data) when is_map(data) do
          data =
            for {key, val} <- data do
              {String.to_existing_atom(key), val}
            end
          {:ok, struct!(URI, data)}
        end

        # When dumping data to the database, we *expect* an URI struct
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

  """

  import Kernel, except: [match?: 2]

  @doc false
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Ecto.Type
      def embed_as(_), do: :self
      def equal?(term1, term2), do: term1 == term2
      defoverridable [embed_as: 1, equal?: 2]
    end
  end

  @typedoc "An Ecto type, primitive or custom."
  @type t :: primitive | custom

  @typedoc "Primitive Ecto types (handled by Ecto)."
  @type primitive :: base | composite

  @typedoc "Custom types are represented by user-defined modules."
  @type custom :: module

  @type base :: :integer | :float | :boolean | :string | :map |
                 :binary | :decimal | :id | :binary_id |
                 :utc_datetime | :naive_datetime | :date | :time | :any |
                 :utc_datetime_usec | :naive_datetime_usec | :time_usec

  @type composite :: {:array, t} | {:map, t} | private_composite

  @typep private_composite :: {:maybe, t} | {:embed, Ecto.Embedded.t} | {:in, t}

  @base ~w(
    integer float decimal boolean string map binary id binary_id any
    utc_datetime naive_datetime date time
    utc_datetime_usec naive_datetime_usec time_usec
  )a
  @composite ~w(array map in embed param)a

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

  When returning `{:error, keyword()}`, the returned keyword list
  will be preserved in the changeset errors, similar to
  `Ecto.Changeset.add_error/4`. Passing a `:message` key, will override
  the default message. It is not possible to override the `:type` key.

  For `{:array, CustomType}` or `{:map, CustomType}` the returned
  keyword list will be erased and the default error will be shown.
  """
  @callback cast(term) :: {:ok, term} | {:error, keyword()} | :error

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
  """
  @callback equal?(term, term) :: boolean

  @doc """
  Dictates how the type should be treated inside embeds.

  By default, the type is sent as itself, without calling
  dumping to keep the higher level representation. But
  it can be set to `:dump` to it is dumped before encoded.
  """
  @callback embed_as(format :: atom) :: :self | :dump

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
  def primitive?({composite, _}) when composite in @composite, do: true
  def primitive?(base) when base in @base, do: true
  def primitive?(_), do: false

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
  def embed_as({composite, _}, _format) when composite in @composite, do: :self
  def embed_as(base, _format) when base in @base, do: :self
  def embed_as(mod, format) do
    if loaded_and_exported?(mod, :embed_as, 1) do
      mod.embed_as(format)
    else
      :self
    end
  end

  @doc """
  Dumps the `value` for `type` considering it will be embedded in `format`.

  ## Examples

      iex> Ecto.Type.embedded_dump(:decimal, Decimal.new("1"), :json)
      {:ok, Decimal.new("1")}

  """
  def embedded_dump({:embed, _} = type, value, format) do
    dump(type, value, &embedded_dump(&1, &2, format))
  end

  def embedded_dump(type, value, format) do
    case embed_as(type, format) do
      :self -> {:ok, value}
      :dump -> dump(type, value)
    end
  end

  @doc """
  Loads the `value` for `type` considering it was embedded in `format`.

  ## Examples

      iex> Ecto.Type.embedded_load(:decimal, "1", :json)
      {:ok, Decimal.new("1")}

  """
  def embedded_load({:embed, _} = type, value, format) do
    load(type, value, &embedded_load(&1, &2, format))
  end

  def embedded_load(type, value, format) do
    case embed_as(type, format) do
      :self ->
        case cast(type, value) do
          {:ok, _} = ok -> ok
          _ -> :error
        end

      :dump ->
        load(type, value)
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
  def type({:array, type}), do: {:array, type(type)}
  def type({:map, type}), do: {:map, type(type)}

  def type(type) do
    if primitive?(type) do
      type
    else
      type.type
    end
  end

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
      do_match?(schema_type.type, query_type)
    end
  end

  defp do_match?(_left, :any),  do: true
  defp do_match?(:any, _right), do: true
  defp do_match?({outer, left}, {outer, right}), do: match?(left, right)
  defp do_match?({:array, :any}, {:embed, %{cardinality: :many}}), do: true
  defp do_match?(:decimal, type) when type in [:float, :integer], do: true
  defp do_match?(:binary_id, :binary), do: true
  defp do_match?(:id, :integer), do: true
  defp do_match?(type, type), do: true
  defp do_match?(:naive_datetime, {:param, :any_datetime}), do: true
  defp do_match?(:naive_datetime_usec, {:param, :any_datetime}), do: true
  defp do_match?(:utc_datetime, {:param, :any_datetime}), do: true
  defp do_match?(:utc_datetime_usec, {:param, :any_datetime}), do: true
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
  def dump(_type, nil) do
    {:ok, nil}
  end

  def dump({:maybe, type}, value) do
    case dump(type, value) do
      {:ok, _} = ok -> ok
      :error -> {:ok, value}
    end
  end

  def dump(type, value) do
    dump_fun(type).(value)
  end

  @doc """
  Dumps a value to the given type.

  This function behaves the same as `dump/2`, except for composite types
  the given `dumper` function is used.
  """
  @spec dump(t, term, (t, term -> {:ok, term} | :error)) :: {:ok, term} | :error
  def dump(_type, nil, _dumper) do
    {:ok, nil}
  end

  def dump({:maybe, type}, value, dumper) do
    case dump(type, value, dumper) do
      {:ok, _} = ok -> ok
      :error -> {:ok, value}
    end
  end

  def dump({:embed, embed}, value, dumper) do
    dump_embed(embed, value, dumper)
  end

  def dump({:in, type}, value, dumper) do
    case dump({:array, type}, value, dumper) do
      {:ok, value} -> {:ok, {:in, value}}
      :error -> :error
    end
  end

  def dump({:map, type}, value, dumper) when is_map(value) do
    map(Map.to_list(value), type, dumper, %{})
  end

  def dump({:array, type}, value, dumper) do
    array(value, type, dumper, [])
  end

  def dump(type, value, _) do
    dump_fun(type).(value)
  end

  defp dump_fun(:integer), do: &same_integer/1
  defp dump_fun(:float), do: &dump_float/1
  defp dump_fun(:boolean), do: &same_boolean/1
  defp dump_fun(:map), do: &same_map/1
  defp dump_fun(:string), do: &same_binary/1
  defp dump_fun(:binary), do: &same_binary/1
  defp dump_fun(:id), do: &same_integer/1
  defp dump_fun(:binary_id), do: &same_binary/1
  defp dump_fun(:any), do: &{:ok, &1}
  defp dump_fun(:decimal), do: &same_decimal/1
  defp dump_fun(:date), do: &same_date/1
  defp dump_fun(:time), do: &dump_time/1
  defp dump_fun(:time_usec), do: &dump_time_usec/1
  defp dump_fun(:naive_datetime), do: &dump_naive_datetime/1
  defp dump_fun(:naive_datetime_usec), do: &dump_naive_datetime_usec/1
  defp dump_fun(:utc_datetime), do: &dump_utc_datetime/1
  defp dump_fun(:utc_datetime_usec), do: &dump_utc_datetime_usec/1
  defp dump_fun({:param, :any_datetime}), do: &dump_any_datetime/1
  defp dump_fun({:array, type}), do: &array(&1, dump_fun(type), [])
  defp dump_fun({:map, type}), do: &map(&1, dump_fun(type), %{})
  defp dump_fun(mod) when is_atom(mod), do: &mod.dump(&1)

  defp dump_float(term) when is_float(term), do: {:ok, term}
  defp dump_float(_), do: :error

  defp dump_time(%Time{} = term), do: {:ok, check_no_usec!(term, :time)}
  defp dump_time(_), do: :error

  defp dump_time_usec(%Time{} = term), do: {:ok, check_usec!(term, :time_usec)}
  defp dump_time_usec(_), do: :error

  defp dump_any_datetime(%NaiveDateTime{} = term), do: {:ok, term}
  defp dump_any_datetime(%DateTime{} = term), do: {:ok, term}
  defp dump_any_datetime(_), do: :error

  defp dump_naive_datetime(%NaiveDateTime{} = term), do:
    {:ok, check_no_usec!(term, :naive_datetime)}

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

  defp dump_embed(%{cardinality: :one, related: schema, field: field},
                  value, fun) when is_map(value) do
    {:ok, dump_embed(field, schema, value, schema.__schema__(:dump), fun)}
  end

  defp dump_embed(%{cardinality: :many, related: schema, field: field},
                  value, fun) when is_list(value) do
    types = schema.__schema__(:dump)
    {:ok, Enum.map(value, &dump_embed(field, schema, &1, types, fun))}
  end

  defp dump_embed(_embed, _value, _fun) do
    :error
  end

  defp dump_embed(_field, schema, %{__struct__: schema} = struct, types, dumper) do
    Ecto.Schema.Loader.safe_dump(struct, types, dumper)
  end

  defp dump_embed(field, _schema, value, _types, _fun) do
    raise ArgumentError, "cannot dump embed `#{field}`, invalid value: #{inspect value}"
  end

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
  def load({:embed, embed}, value) do
    load_embed(embed, value, &load/2)
  end

  def load(_type, nil) do
    {:ok, nil}
  end

  def load({:maybe, type}, value) do
    case load(type, value) do
      {:ok, _} = ok -> ok
      :error -> {:ok, value}
    end
  end

  def load(type, value) do
    load_fun(type).(value)
  end

  @doc """
  Loads a value with the given type.

  This function behaves the same as `load/2`, except for composite types
  the given `loader` function is used.
  """
  @spec load(t, term, (t, term -> {:ok, term} | :error)) :: {:ok, term} | :error
  def load({:embed, embed}, value, loader) do
    load_embed(embed, value, loader)
  end

  def load(_type, nil, _loader) do
    {:ok, nil}
  end

  def load({:maybe, type}, value, loader) do
    case load(type, value, loader) do
      {:ok, _} = ok -> ok
      :error -> {:ok, value}
    end
  end

  def load({:map, type}, value, loader) when is_map(value) do
    map(Map.to_list(value), type, loader, %{})
  end

  def load({:array, type}, value, loader) do
    array(value, type, loader, [])
  end

  def load(type, value, _loader) do
    load_fun(type).(value)
  end

  defp load_fun(:integer), do: &same_integer/1
  defp load_fun(:float), do: &load_float/1
  defp load_fun(:boolean), do: &same_boolean/1
  defp load_fun(:map), do: &same_map/1
  defp load_fun(:string), do: &same_binary/1
  defp load_fun(:binary), do: &same_binary/1
  defp load_fun(:id), do: &same_integer/1
  defp load_fun(:binary_id), do: &same_binary/1
  defp load_fun(:any), do: &{:ok, &1}
  defp load_fun(:decimal), do: &same_decimal/1
  defp load_fun(:date), do: &same_date/1
  defp load_fun(:time), do: &load_time/1
  defp load_fun(:time_usec), do: &load_time_usec/1
  defp load_fun(:naive_datetime), do: &load_naive_datetime/1
  defp load_fun(:naive_datetime_usec), do: &load_naive_datetime_usec/1
  defp load_fun(:utc_datetime), do: &load_utc_datetime/1
  defp load_fun(:utc_datetime_usec), do: &load_utc_datetime_usec/1
  defp load_fun({:array, type}), do: &array(&1, load_fun(type), [])
  defp load_fun({:map, type}), do: &map(&1, load_fun(type), %{})
  defp load_fun(mod) when is_atom(mod), do: &mod.load(&1)

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
    do: {:ok, datetime |> check_utc_timezone!(:naive_datetime) |> DateTime.to_naive() |> truncate_usec()}

  defp load_naive_datetime(%NaiveDateTime{} = naive_datetime),
    do: {:ok, truncate_usec(naive_datetime)}

  defp load_naive_datetime(_), do: :error

  defp load_naive_datetime_usec(%DateTime{} = datetime),
    do: {:ok, datetime |> check_utc_timezone!(:naive_datetime_usec) |> DateTime.to_naive() |> pad_usec()}

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

  defp load_embed(%{cardinality: :one}, nil, _fun), do: {:ok, nil}

  defp load_embed(%{cardinality: :one, related: schema, field: field},
                  value, fun) when is_map(value) do
    {:ok, load_embed(field, schema, value, fun)}
  end

  defp load_embed(%{cardinality: :many}, nil, _fun), do: {:ok, []}

  defp load_embed(%{cardinality: :many, related: schema, field: field},
                  value, fun) when is_list(value) do
    {:ok, Enum.map(value, &load_embed(field, schema, &1, fun))}
  end

  defp load_embed(_embed, _value, _fun) do
    :error
  end

  defp load_embed(_field, schema, value, loader) when is_map(value) do
    Ecto.Schema.Loader.unsafe_load(schema, value, loader)
  end

  defp load_embed(field, _schema, value, _fun) do
    raise ArgumentError, "cannot load embed `#{field}`, invalid value: #{inspect value}"
  end

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

      iex> cast({:array, :integer}, [1, 2, 3])
      {:ok, [1, 2, 3]}
      iex> cast({:array, :integer}, ["1", "2", "3"])
      {:ok, [1, 2, 3]}
      iex> cast({:array, :string}, [1, 2, 3])
      :error
      iex> cast(:string, [1, 2, 3])
      :error

  """
  @spec cast(t, term) :: {:ok, term} | {:error, keyword()} | :error
  def cast({:embed, type}, value), do: cast_embed(type, value)
  def cast({:in, _type}, nil), do: :error
  def cast(_type, nil), do: {:ok, nil}

  def cast({:maybe, type}, value) do
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
  defp cast_fun({:param, :any_datetime}), do: &cast_any_datetime(&1)
  defp cast_fun({:in, type}), do: &array(&1, cast_fun(type), [])
  defp cast_fun({:array, type}), do: &array(&1, cast_fun(type), [])
  defp cast_fun({:map, type}), do: &map(&1, cast_fun(type), %{})
  defp cast_fun(mod) when is_atom(mod), do: &mod.cast(&1)

  defp cast_integer(term) when is_binary(term) do
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
      {:ok, decimal} -> check_decimal(decimal, false)
      {decimal, ""} -> check_decimal(decimal, false)
      :error -> :error
    end
  end
  defp cast_decimal(term), do: same_decimal(term)

  defp cast_boolean(term) when term in ~w(true 1),  do: {:ok, true}
  defp cast_boolean(term) when term in ~w(false 0), do: {:ok, false}
  defp cast_boolean(term) when is_boolean(term), do: {:ok, term}
  defp cast_boolean(_), do: :error

  defp cast_binary(term) when is_binary(term), do: {:ok, term}
  defp cast_binary(_), do: :error

  defp cast_map(term) when is_map(term), do: {:ok, term}
  defp cast_map(_), do: :error

  defp cast_embed(%{cardinality: :one}, nil), do: {:ok, nil}
  defp cast_embed(%{cardinality: :one, related: schema}, %{__struct__: schema} = struct) do
    {:ok, struct}
  end

  defp cast_embed(%{cardinality: :many}, nil), do: {:ok, []}
  defp cast_embed(%{cardinality: :many, related: schema}, value) when is_list(value) do
    if Enum.all?(value, &Kernel.match?(%{__struct__: ^schema}, &1)) do
      {:ok, value}
    else
      :error
    end
  end

  defp cast_embed(_embed, _value) do
    :error
  end

  ## Shared helpers

  defp same_integer(term) when is_integer(term), do: {:ok, term}
  defp same_integer(_), do: :error

  defp same_boolean(term) when is_boolean(term), do: {:ok, term}
  defp same_boolean(_), do: :error

  defp same_binary(term) when is_binary(term), do: {:ok, term}
  defp same_binary(_), do: :error

  defp same_map(term) when is_map(term), do: {:ok, term}
  defp same_map(_), do: :error

  defp same_decimal(term) when is_integer(term), do: {:ok, Decimal.new(term)}
  defp same_decimal(term) when is_float(term), do: {:ok, Decimal.from_float(term)}
  defp same_decimal(%Decimal{} = term), do: check_decimal(term, true)
  defp same_decimal(_), do: :error

  defp same_date(%Date{} = term), do: {:ok, term}
  defp same_date(_), do: :error

  ## Adapter related

  @doc false
  def adapter_autogenerate(adapter, type) do
    type
    |> type()
    |> adapter.autogenerate()
  end

  @doc false
  def adapter_load(_adapter, {:embed, embed}, nil) do
    load_embed(embed, nil, &load/2)
  end
  def adapter_load(_adapter, _type, nil) do
    {:ok, nil}
  end
  def adapter_load(adapter, {:maybe, type}, value) do
    case adapter_load(adapter, type, value) do
      {:ok, _} = ok -> ok
      :error -> {:ok, value}
    end
  end
  def adapter_load(adapter, type, value) do
    if of_base_type?(type, value) do
      {:ok, value}
    else
      process_loaders(adapter.loaders(type(type), type), {:ok, value}, adapter)
    end
  end

  defp process_loaders(_, :error, _adapter),
    do: :error
  defp process_loaders([fun|t], {:ok, value}, adapter) when is_function(fun),
    do: process_loaders(t, fun.(value), adapter)
  defp process_loaders([type|t], {:ok, value}, adapter),
    do: process_loaders(t, load(type, value, &adapter_load(adapter, &1, &2)), adapter)
  defp process_loaders([], {:ok, _} = acc, _adapter),
    do: acc

  @doc false
  def adapter_dump(_adapter, type, nil),
    do: dump(type, nil)
  def adapter_dump(adapter, {:maybe, type}, value) do
    case adapter_dump(adapter, type, value) do
      {:ok, _} = ok -> ok
      :error -> {:ok, value}
    end
  end
  def adapter_dump(adapter, type, value),
    do: process_dumpers(adapter.dumpers(type(type), type), {:ok, value}, adapter)

  defp process_dumpers(_, :error, _adapter),
    do: :error
  defp process_dumpers([fun|t], {:ok, value}, adapter) when is_function(fun),
    do: process_dumpers(t, fun.(value), adapter)
  defp process_dumpers([type|t], {:ok, value}, adapter),
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

  defp cast_date(year, month, day) when is_integer(year) and is_integer(month) and is_integer(day) do
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
    do: cast_time(to_i(hour), to_i(minute), to_i(Map.get(map, "second")), to_i(Map.get(map, "microsecond")))
  defp cast_time(%{hour: hour, minute: minute, second: second, microsecond: {microsecond, precision}}),
    do: cast_time(to_i(hour), to_i(minute), to_i(second), {to_i(microsecond), to_i(precision)})
  defp cast_time(%{hour: hour, minute: minute} = map),
    do: cast_time(to_i(hour), to_i(minute), to_i(Map.get(map, :second)), to_i(Map.get(map, :microsecond)))
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

  defp cast_naive_datetime(<<year::4-bytes, ?-, month::2-bytes, ?-, day::2-bytes, sep, hour::2-bytes, ?:, minute::2-bytes>>)
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

  defp cast_naive_datetime(%{"year" => empty, "month" => empty, "day" => empty,
                             "hour" => empty, "minute" => empty}) when empty in ["", nil],
    do: {:ok, nil}

  defp cast_naive_datetime(%{year: empty, month: empty, day: empty,
                             hour: empty, minute: empty}) when empty in ["", nil],
    do: {:ok, nil}

  defp cast_naive_datetime(%{} = map) do
    with {:ok, %Date{} = date} <- cast_date(map),
         {:ok, %Time{} = time} <- cast_time(map) do
      case NaiveDateTime.new(date, time) do
        {:ok, _} = ok -> ok
        {:error, _} -> :error
      end
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

  defp cast_utc_datetime(<<year::4-bytes, ?-, month::2-bytes, ?-, day::2-bytes, sep, hour::2-bytes, ?:, minute::2-bytes>>)
       when sep in [?\s, ?T] do
    case NaiveDateTime.new(to_i(year), to_i(month), to_i(day), to_i(hour), to_i(minute), 0) do
      {:ok, naive_datetime} -> {:ok, DateTime.from_naive!(naive_datetime, "Etc/UTC")}
      _ -> :error
    end
  end

  defp cast_utc_datetime(binary) when is_binary(binary) do
    case DateTime.from_iso8601(binary) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, :missing_offset} ->
        case NaiveDateTime.from_iso8601(binary) do
          {:ok, naive_datetime} -> {:ok, DateTime.from_naive!(naive_datetime, "Etc/UTC")}
          {:error, _} -> :error
        end
      {:error, _} -> :error
    end
  end
  defp cast_utc_datetime(%DateTime{time_zone: "Etc/UTC"} = datetime), do: {:ok, datetime}
  defp cast_utc_datetime(%DateTime{} = datetime) do
    case (datetime |> DateTime.to_unix(:microsecond) |> DateTime.from_unix(:microsecond)) do
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

  defp equal_fun(nil), do: nil
  defp equal_fun(:decimal), do: &equal_decimal?/2
  defp equal_fun(t) when t in [:time, :time_usec], do: &equal_time?/2
  defp equal_fun(t) when t in [:utc_datetime, :utc_datetime_usec], do: &equal_utc_datetime?/2
  defp equal_fun(t) when t in [:naive_datetime, :naive_datetime_usec], do: &equal_naive_datetime?/2
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

  defp equal_fun(mod) when is_atom(mod) do
    if loaded_and_exported?(mod, :equal?, 2) do
      &mod.equal?/2
    end
  end

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

  # nil always passes through
  defp array([nil | t], fun, acc) do
    array(t, fun, [nil | acc])
  end

  defp array([h | t], fun, acc) do
    case fun.(h) do
      {:ok, h} -> array(t, fun, [h | acc])
      :error -> :error
      {:error, _custom_errors} -> :error
    end
  end

  defp array([], _fun, acc) do
    {:ok, Enum.reverse(acc)}
  end

  defp array(_, _, _) do
    :error
  end

  defp map(map, fun, acc) when is_map(map) do
    map(Map.to_list(map), fun, acc)
  end

  # nil always passes through
  defp map([{key, nil} | t], fun, acc) do
    map(t, fun, Map.put(acc, key, nil))
  end
  defp map([{key, value} | t], fun, acc) do
    case fun.(value) do
      {:ok, value} -> map(t, fun, Map.put(acc, key, value))
      :error -> :error
      {:error, _custom_errors} -> :error
    end
  end

  defp map([], _fun, acc) do
    {:ok, acc}
  end

  defp map(_, _, _) do
    :error
  end

  defp array([h | t], type, fun, acc) do
    case fun.(type, h) do
      {:ok, h} -> array(t, type, fun, [h | acc])
      :error -> :error
    end
  end

  defp array([], _type, _fun, acc) do
    {:ok, Enum.reverse(acc)}
  end

  defp array(_, _, _, _) do
    :error
  end

  defp map([{key, value} | t], type, fun, acc) do
    case fun.(type, value) do
      {:ok, value} -> map(t, type, fun, Map.put(acc, key, value))
      :error -> :error
    end
  end

  defp map([], _type, _fun, acc) do
    {:ok, acc}
  end

  defp map(_, _, _, _) do
    :error
  end

  defp to_i(nil), do: nil
  defp to_i(int) when is_integer(int), do: int
  defp to_i(bin) when is_binary(bin) do
    case Integer.parse(bin) do
      {int, ""} -> int
      _ -> nil
    end
  end

  @compile {:inline, loaded_and_exported?: 3}
  # TODO: Remove this function when all Ecto types have been updated.
  defp loaded_and_exported?(module, fun, arity) do
    if :erlang.module_loaded(module) or Code.ensure_loaded?(module) do
      function_exported?(module, fun, arity)
    else
      raise ArgumentError, "cannot use #{inspect(module)} as Ecto.Type, module is not available"
    end
  end

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
          "#{inspect kind} expects the time zone to be \"Etc/UTC\", got `#{inspect(datetime)}`"
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
