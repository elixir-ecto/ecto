defmodule Ecto.Type do
  @moduledoc """
  Defines functions and the `Ecto.Type` behaviour for implementing
  custom types.

  A custom type expects 4 functions to be implemented, all documented
  and described below. We also provide two examples of how custom
  types can be used in Ecto to augment existing types or providing
  your own types.

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
        @behaviour Ecto.Type
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

        # When loading data from the database, we are guaranteed to
        # receive a map (as databases are strict) and we will
        # just put the data back into an URI struct to be stored 
        # in the loaded schema struct.
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

  @typedoc "An Ecto type, primitive or custom."
  @type t         :: primitive | custom

  @typedoc "Primitive Ecto types (handled by Ecto)."
  @type primitive :: base | composite

  @typedoc "Custom types are represented by user-defined modules."
  @type custom    :: atom

  @typep base      :: :integer | :float | :boolean | :string | :map |
                      :binary | :decimal | :id | :binary_id |
                      :utc_datetime  | :naive_datetime | :date | :time | :any
  @typep composite :: {:array, t} | {:map, t} | {:embed, Ecto.Embedded.t} | {:in, t}

  @base      ~w(integer float boolean string binary decimal datetime utc_datetime naive_datetime date time id binary_id map any)a
  @composite ~w(array map in embed)a

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

  """
  @callback cast(term) :: {:ok, term} | :error

  @doc """
  Loads the given term into a custom type.

  This callback is called when loading data from the database and
  receive an Ecto native type. It can return any type, as long as
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

  A `dumper` function may be given for handling recursive types.
  """
  @spec dump(t, term, (t, term -> {:ok, term} | :error)) :: {:ok, term} | :error
  def dump(type, value, dumper \\ &dump/2)

  def dump(_type, nil, _dumper) do
    {:ok, nil}
  end

  def dump(:binary_id, value, _dumper) when is_binary(value) do
    {:ok, value}
  end

  def dump(:any, value, _dumper) do
    Ecto.DataType.dump(value)
  end

  def dump({:embed, embed}, value, dumper) do
    dump_embed(embed, value, dumper)
  end

  def dump({:array, type}, value, dumper) when is_list(value) do
    array(value, type, dumper, [])
  end

  def dump({:map, type}, value, dumper) when is_map(value) do
    map(Map.to_list(value), type, dumper, %{})
  end

  def dump({:in, type}, value, dumper) do
    case dump({:array, type}, value, dumper) do
      {:ok, v} -> {:ok, {:in, v}}
      :error -> :error
    end
  end

  def dump(:decimal, term, _dumper) when is_number(term) do
    {:ok, Decimal.new(term)}
  end

  def dump(:date, term, _dumper) do
    dump_date(term)
  end

  def dump(:time, term, _dumper) do
    dump_time(term)
  end

  def dump(:naive_datetime, term, _dumper) do
    dump_naive_datetime(term)
  end

  def dump(:utc_datetime, term, _dumper) do
    dump_utc_datetime(term)
  end

  def dump(type, value, _dumper) do
    cond do
      not primitive?(type) ->
        type.dump(value)
      of_base_type?(type, value) ->
        {:ok, value}
      true ->
        :error
    end
  end

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
    Enum.reduce(types, %{}, fn {field, {source, type}}, acc ->
      value = Map.get(struct, field)

      case dumper.(type, value) do
        {:ok, value} ->
          Map.put(acc, source, value)
        :error ->
          raise ArgumentError, "cannot dump `#{inspect value}` as type #{inspect type} " <>
                               "for field `#{field}` in schema #{inspect schema}"
      end
    end)
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

  A `loader` function may be given for handling recursive types.
  """
  @spec load(t, term, (t, term -> {:ok, term} | :error)) :: {:ok, term} | :error
  def load(type, value, loader \\ &load/2)

  def load({:embed, embed}, value, loader) do
    load_embed(embed, value, loader)
  end

  def load(_type, nil, _loader), do: {:ok, nil}

  def load(:binary_id, value, _loader) when is_binary(value) do
    {:ok, value}
  end

  def load({:array, type}, value, loader) when is_list(value) do
    array(value, type, loader, [])
  end

  def load({:map, type}, value, loader) when is_map(value) do
    map(Map.to_list(value), type, loader, %{})
  end

  def load(:date, term, _loader) do
    load_date(term)
  end

  def load(:time, term, _loader) do
    load_time(term)
  end

  def load(:naive_datetime, term, _loader) do
    load_naive_datetime(term)
  end

  def load(:utc_datetime, term, _loader) do
    load_utc_datetime(term)
  end

  def load(type, value, _loader) do
    cond do
      not primitive?(type) ->
        type.load(value)
      of_base_type?(type, value) ->
        {:ok, value}
      true ->
        :error
    end
  end

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
    Ecto.Schema.__unsafe_load__(schema, value, loader)
  end

  defp load_embed(field, _schema, value, _fun) do
    raise ArgumentError, "cannot load embed `#{field}`, invalid value: #{inspect value}"
  end

  @doc """
  Casts a value to the given type.

  `cast/2` is used by the finder queries and changesets
  to cast outside values to specific types.

  Note that nil can be cast to all primitive types as data
  stores allow nil to be set on any column.

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

      iex> cast(:decimal, Decimal.new(1.0))
      {:ok, Decimal.new(1.0)}
      iex> cast(:decimal, Decimal.new("1.0"))
      {:ok, Decimal.new(1.0)}

      iex> cast({:array, :integer}, [1, 2, 3])
      {:ok, [1, 2, 3]}
      iex> cast({:array, :integer}, ["1", "2", "3"])
      {:ok, [1, 2, 3]}
      iex> cast({:array, :string}, [1, 2, 3])
      :error
      iex> cast(:string, [1, 2, 3])
      :error

  """
  @spec cast(t, term) :: {:ok, term} | :error
  def cast({:embed, type}, value) do
    cast_embed(type, value)
  end

  def cast({:in, _type}, nil), do: :error
  def cast(_type, nil), do: {:ok, nil}

  def cast(:binary_id, value) when is_binary(value) do
    {:ok, value}
  end

  def cast({:array, type}, term) when is_list(term) do
    array(term, type, &cast/2, [])
  end

  def cast({:map, type}, term) when is_map(term) do
    map(Map.to_list(term), type, &cast/2, %{})
  end

  def cast({:in, type}, term) when is_list(term) do
    array(term, type, &cast/2, [])
  end

  def cast(:float, term) when is_binary(term) do
    case Float.parse(term) do
      {float, ""} -> {:ok, float}
      _           -> :error
    end
  end
  def cast(:float, term) when is_integer(term), do: {:ok, term + 0.0}

  def cast(:boolean, term) when term in ~w(true 1),  do: {:ok, true}
  def cast(:boolean, term) when term in ~w(false 0), do: {:ok, false}

  def cast(:decimal, term) when is_binary(term) do
    Decimal.parse(term)
  end
  def cast(:decimal, term) when is_number(term) do
    {:ok, Decimal.new(term)}
  end

  def cast(:date, term) do
    cast_date(term)
  end

  def cast(:time, term) do
    cast_time(term)
  end

  def cast(:naive_datetime, term) do
    cast_naive_datetime(term)
  end

  def cast(:utc_datetime, term) do
    cast_utc_datetime(term)
  end

  def cast(type, term) when type in [:id, :integer] and is_binary(term) do
    case Integer.parse(term) do
      {int, ""} -> {:ok, int}
      _         -> :error
    end
  end

  def cast(type, term) do
    cond do
      not primitive?(type) ->
        type.cast(term)
      of_base_type?(type, term) ->
        {:ok, term}
      true ->
        :error
    end
  end

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

  ## Adapter related

  @doc false
  def adapter_load(_adapter, type, nil) do
    load(type, nil)
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

  defp dump_date(%Date{year: year, month: month, day: day}),
    do: {:ok, {year, month, day}}
  defp dump_date(%{__struct__: _} = struct),
    do: Ecto.DataType.dump(struct)
  defp dump_date(_),
    do: :error

  defp load_date(%Date{} = date),
    do: {:ok, date}
  defp load_date({year, month, day}),
    do: {:ok, %Date{year: year, month: month, day: day}}
  defp load_date(_),
    do: :error

  ## Time

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

  defp dump_time(%Time{hour: hour, minute: minute, second: second, microsecond: {microsecond, _}}),
    do: {:ok, {hour, minute, second, microsecond}}
  defp dump_time(%{__struct__: _} = struct),
    do: Ecto.DataType.dump(struct)
  defp dump_time(_),
    do: :error

  defp load_time(%Time{} = time),
    do: {:ok, time}
  defp load_time({hour, minute, second, microsecond}),
    do: {:ok, %Time{hour: hour, minute: minute, second: second, microsecond: {microsecond, 6}}}
  defp load_time({hour, minute, second}),
    do: {:ok, %Time{hour: hour, minute: minute, second: second}}
  defp load_time(_),
    do: :error

  ## Naive datetime

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
    with {:ok, date} <- cast_date(map),
         {:ok, time} <- cast_time(map) do
      case NaiveDateTime.new(date, time) do
        {:ok, _} = ok -> ok
        {:error, _} -> :error
      end
    end
  end

  defp dump_naive_datetime(%NaiveDateTime{year: year, month: month, day: day,
                                          hour: hour, minute: minute, second: second, microsecond: {microsecond, _}}),
    do: {:ok, {{year, month, day}, {hour, minute, second, microsecond}}}
  defp dump_naive_datetime(%{__struct__: _} = struct),
    do: Ecto.DataType.dump(struct)
  defp dump_naive_datetime(_),
    do: :error

  defp load_naive_datetime(%NaiveDateTime{} = naive),
    do: {:ok, naive}
  defp load_naive_datetime({{year, month, day}, {hour, minute, second, microsecond}}),
    do: {:ok, %NaiveDateTime{year: year, month: month, day: day,
                             hour: hour, minute: minute, second: second, microsecond: {microsecond, 6}}}
  defp load_naive_datetime({{year, month, day}, {hour, minute, second}}),
    do: {:ok, %NaiveDateTime{year: year, month: month, day: day,
                             hour: hour, minute: minute, second: second}}
  defp load_naive_datetime(_),
    do: :error

  ## UTC datetime

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
    case (datetime |> DateTime.to_unix() |> DateTime.from_unix()) do
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

  defp dump_utc_datetime(%DateTime{year: year, month: month, day: day, time_zone: "Etc/UTC",
                                   hour: hour, minute: minute, second: second, microsecond: {microsecond, _}}),
    do: {:ok, {{year, month, day}, {hour, minute, second, microsecond}}}
  defp dump_utc_datetime(%{__struct__: _} = struct),
    do: Ecto.DataType.dump(struct)
  defp dump_utc_datetime(_),
    do: :error

  defp load_utc_datetime(%DateTime{} = dt),
    do: {:ok, dt}
  defp load_utc_datetime({{year, month, day}, {hour, minute, second, microsecond}}),
    do: {:ok, %DateTime{year: year, month: month, day: day,
                        hour: hour, minute: minute, second: second, microsecond: {microsecond, 6},
                        std_offset: 0, utc_offset: 0, zone_abbr: "UTC", time_zone: "Etc/UTC"}}
  defp load_utc_datetime({{year, month, day}, {hour, minute, second}}),
    do: {:ok, %DateTime{year: year, month: month, day: day,
                        hour: hour, minute: minute, second: second,
                        std_offset: 0, utc_offset: 0, zone_abbr: "UTC", time_zone: "Etc/UTC"}}
  defp load_utc_datetime(_),
    do: :error

  ## Helpers

  # Checks if a value is of the given primitive type.
  defp of_base_type?(:any, _),           do: true
  defp of_base_type?(:id, term),         do: is_integer(term)
  defp of_base_type?(:float, term),      do: is_float(term)
  defp of_base_type?(:integer, term),    do: is_integer(term)
  defp of_base_type?(:boolean, term),    do: is_boolean(term)
  defp of_base_type?(:binary, term),     do: is_binary(term)
  defp of_base_type?(:string, term),     do: is_binary(term)
  defp of_base_type?(:map, term),        do: is_map(term) and not Map.has_key?(term, :__struct__)
  defp of_base_type?(:decimal, value),   do: Kernel.match?(%{__struct__: Decimal}, value)
  defp of_base_type?(_, _),              do: false

  defp array([h|t], type, fun, acc) do
    case fun.(type, h) do
      {:ok, h} -> array(t, type, fun, [h|acc])
      :error   -> :error
    end
  end

  defp array([], _type, _fun, acc) do
    {:ok, Enum.reverse(acc)}
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

  defp map(_, _, _, _), do: :error

  defp to_i(nil), do: nil
  defp to_i(int) when is_integer(int), do: int
  defp to_i(bin) when is_binary(bin) do
    case Integer.parse(bin) do
      {int, ""} -> int
      _ -> nil
    end
  end
end
