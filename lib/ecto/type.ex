defmodule Ecto.Type do
  @moduledoc """
  Defines functions and the `Ecto.Type` behaviour for implementing
  custom types.

  A custom type expects 4 functions to be implemented, all documented
  and described below. We also provide two examples of how custom
  types can be used in Ecto to augment existing types or providing
  your own types.

  ## Example

  Imagine you want to support your id field to be looked up as a
  permalink. For example, you want the following query to work:

      permalink = "10-how-to-be-productive-with-elixir"
      from p in Post, where: p.id == ^permalink

  If `id` is an integer field, Ecto will fail in the query above
  because it cannot cast the string to an integer. By using a
  custom type, we can provide special casting behaviour while
  still keeping the underlying Ecto type the same:

      defmodule Permalink do
        @behaviour Ecto.Type
        def type, do: :integer

        # Provide our own casting rules.
        def cast(string) when is_binary(string) do
          case Integer.parse(string) do
            {int, _} -> {:ok, int}
            :error   -> :error
          end
        end

        # We should still accept integers
        def cast(integer) when is_integer(integer), do: {:ok, integer}

        # Everything else is a failure though
        def cast(_), do: :error

        # When loading data from the database, we are guaranteed to
        # receive an integer (as databases are strict) and we will
        # just return it to be stored in the schema struct.
        def load(integer) when is_integer(integer), do: {:ok, integer}

        # When dumping data to the database, we *expect* an integer
        # but any value could be inserted into the struct, so we need
        # guard against them.
        def dump(integer) when is_integer(integer), do: {:ok, integer}
        def dump(_), do: :error
      end

  Now we can use our new field above as our primary key type in schemas:

      defmodule Post do
        use Ecto.Schema

        @primary_key {:id, Permalink, autogenerate: true}
        schema "posts" do
          ...
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

  # Types that we cannot optimize loading
  @bypass @base -- [:utc_datetime, :naive_datetime, :date, :time]

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
  value back into an Ecto native type. There are two situations where
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

  def dump(:any, value, _dumper) do
    Ecto.DataType.dump(value)
  end

  def dump({:embed, embed}, value, dumper) do
    dump_embed(embed, value, dumper)
  end

  def dump({:array, type}, value, dumper) when is_list(value) do
    array(value, &dumper.(type, &1), [])
  end

  def dump({:map, type}, value, dumper) when is_map(value) do
    map(Map.to_list(value), &dumper.(type, &1), %{})
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
    {:ok, dump_embed(field, schema, value, schema.__schema__(:types), fun)}
  end

  defp dump_embed(%{cardinality: :many, related: schema, field: field},
                  value, fun) when is_list(value) do
    types = schema.__schema__(:types)
    {:ok, Enum.map(value, &dump_embed(field, schema, &1, types, fun))}
  end

  defp dump_embed(_embed, _value, _fun) do
    :error
  end

  defp dump_embed(_field, schema, %{__struct__: schema} = struct, types, dumper) do
    Enum.reduce(types, %{}, fn {field, type}, acc ->
      value = Map.get(struct, field)

      case dumper.(type, value) do
        {:ok, value} -> Map.put(acc, field, value)
        :error       -> raise ArgumentError, "cannot dump `#{inspect value}` as type #{inspect type}"
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

  def load({:array, type}, value, loader) when is_list(value) do
    array(value, &loader.(type, &1), [])
  end

  def load({:map, type}, value, loader) when is_map(value) do
    map(Map.to_list(value), &loader.(type, &1), %{})
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
    Ecto.Schema.__load__(schema, nil, nil, nil, value, loader)
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

  def cast(_type, nil), do: {:ok, nil}

  def cast({:array, type}, term) when is_list(term) do
    array(term, &cast(type, &1), [])
  end

  def cast({:map, type}, term) when is_map(term) do
    map(Map.to_list(term), &cast(type, &1), %{})
  end

  def cast({:in, type}, term) when is_list(term) do
    array(term, &cast(type, &1), [])
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
  def adapter_load(_adapter, type, nil),
    do: load(type, nil)
  def adapter_load(adapter, type, value),
    do: do_adapter_load(adapter.loaders(type(type), type), {:ok, value}, adapter)

  defp do_adapter_load(_, :error, _adapter),
    do: :error
  defp do_adapter_load([fun|t], {:ok, value}, adapter) when is_function(fun),
    do: do_adapter_load(t, fun.(value), adapter)
  defp do_adapter_load([type|t], {:ok, _} = acc, adapter) when type in @bypass,
    do: do_adapter_load(t, acc, adapter)
  defp do_adapter_load([type|t], {:ok, value}, adapter),
    do: do_adapter_load(t, load(type, value, &adapter_load(adapter, &1, &2)), adapter)
  defp do_adapter_load([], {:ok, _} = acc, _adapter),
    do: acc

  @doc false
  def adapter_dump(_adapter, type, nil),
    do: dump(type, nil)
  def adapter_dump(adapter, type, value),
    do: do_adapter_dump(adapter.dumpers(type(type), type), {:ok, value}, adapter)

  defp do_adapter_dump(_, :error, _adapter),
    do: :error
  defp do_adapter_dump([fun|t], {:ok, value}, adapter) when is_function(fun),
    do: do_adapter_dump(t, fun.(value), adapter)
  defp do_adapter_dump([type|t], {:ok, value}, adapter),
    do: do_adapter_dump(t, dump(type, value, &adapter_dump(adapter, &1, &2)), adapter)
  defp do_adapter_dump([], {:ok, _} = acc, _adapter),
    do: acc

  ## Date

  defp cast_date(binary) when is_binary(binary) do
    case Date.from_iso8601(binary) do
      {:ok, _} = ok -> ok
      {:error, _} -> :error
    end
  end
  defp cast_date(%{__struct__: _} = struct),
    do: {:ok, struct}
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
  defp cast_time(%{__struct__: _} = struct),
    do: {:ok, struct}
  defp cast_time(%{"hour" => empty, "minute" => empty}) when empty in ["", nil],
    do: {:ok, nil}
  defp cast_time(%{hour: empty, minute: empty}) when empty in ["", nil],
    do: {:ok, nil}
  defp cast_time(%{"hour" => hour, "minute" => minute} = map),
    do: cast_time(to_i(hour), to_i(minute), to_i(map["second"]), to_i(map["microsecond"]))
  defp cast_time(%{hour: hour, minute: minute} = map),
    do: cast_time(to_i(hour), to_i(minute), to_i(map[:second]), to_i(map[:microsecond]))
  defp cast_time(_),
    do: :error

  defp cast_time(hour, minute, sec, usec)
       when is_integer(hour) and is_integer(minute) and
            (is_integer(sec) or is_nil(sec)) and (is_integer(usec) or is_nil(usec)) do
    case Time.new(hour, minute, sec || 0, usec || {0, 0}) do
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
  defp cast_naive_datetime(%{__struct__: _} = struct),
    do: {:ok, struct}
  defp cast_naive_datetime(%{"year" => empty, "month" => empty, "day" => empty,
                             "hour" => empty, "minute" => empty}) when empty in ["", nil],
    do: {:ok, nil}
  defp cast_naive_datetime(%{year: empty, month: empty, day: empty,
                             hour: empty, minute: empty}) when empty in ["", nil],
    do: {:ok, nil}
  defp cast_naive_datetime(%{"year" => year, "month" => month, "day" => day, "hour" => hour, "minute" => min} = map),
    do: cast_naive_datetime(to_i(year), to_i(month), to_i(day),
                            to_i(hour), to_i(min), to_i(map["second"]), to_i(map["microsecond"]))
  defp cast_naive_datetime(%{year: year, month: month, day: day, hour: hour, minute: min} = map),
    do: cast_naive_datetime(to_i(year), to_i(month), to_i(day),
                            to_i(hour), to_i(min), to_i(map[:second]), to_i(map[:microsecond]))
  defp cast_naive_datetime(_),
    do: :error

  defp cast_naive_datetime(year, month, day, hour, minute, sec, usec)
       when is_integer(year) and is_integer(month) and is_integer(day) and
            is_integer(hour) and is_integer(minute) and
            (is_integer(sec) or is_nil(sec)) and (is_integer(usec) or is_nil(usec)) do
    case NaiveDateTime.new(year, month, day, hour, minute, sec || 0, usec || {0, 0}) do
      {:ok, _} = ok -> ok
      {:error, _} -> :error
    end
  end
  defp cast_naive_datetime(_, _, _, _, _, _, _) do
    :error
  end

  defp dump_naive_datetime(%NaiveDateTime{year: year, month: month, day: day,
                                          hour: hour, minute: minute, second: second, microsecond: {microsecond, _}}),
    do: {:ok, {{year, month, day}, {hour, minute, second, microsecond}}}
  defp dump_naive_datetime(%{__struct__: _} = struct),
    do: Ecto.DataType.dump(struct)
  defp dump_naive_datetime(_),
    do: :error

  defp load_naive_datetime({{year, month, day}, {hour, minute, second, microsecond}}),
    do: {:ok, %NaiveDateTime{year: year, month: month, day: day,
                             hour: hour, minute: minute, second: second, microsecond: {microsecond, 6}}}
  defp load_naive_datetime({{year, month, day}, {hour, minute, second}}),
    do: {:ok, %NaiveDateTime{year: year, month: month, day: day,
                             hour: hour, minute: minute, second: second}}
  defp load_naive_datetime(_),
    do: :error

  ## UTC datetime

  defp cast_utc_datetime(value) do
    case cast_naive_datetime(value) do
      {:ok, %NaiveDateTime{year: year, month: month, day: day,
                           hour: hour, minute: minute, second: second, microsecond: microsecond}} ->
        {:ok, %DateTime{year: year, month: month, day: day,
                        hour: hour, minute: minute, second: second, microsecond: microsecond,
                        std_offset: 0, utc_offset: 0, zone_abbr: "UTC", time_zone: "Etc/UTC"}}
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
  defp of_base_type?({:array, _}, _),    do: false # Always handled explicitly.
  defp of_base_type?(:id, term),         do: is_integer(term)
  defp of_base_type?(:float, term),      do: is_float(term)
  defp of_base_type?(:integer, term),    do: is_integer(term)
  defp of_base_type?(:boolean, term),    do: is_boolean(term)
  defp of_base_type?(:binary_id, value), do: is_binary(value)
  defp of_base_type?(:binary, term),     do: is_binary(term)
  defp of_base_type?(:string, term),     do: is_binary(term)
  defp of_base_type?(:map, term),        do: is_map(term) and not Map.has_key?(term, :__struct__)
  defp of_base_type?({:map, _}, _),      do: false # Always handled explicitly.
  defp of_base_type?(:decimal, value),   do: Kernel.match?(%{__struct__: Decimal}, value)

  defp array([h|t], fun, acc) do
    case fun.(h) do
      {:ok, h} -> array(t, fun, [h|acc])
      :error   -> :error
    end
  end

  defp array([], _fun, acc) do
    {:ok, Enum.reverse(acc)}
  end

  defp map([{key, value} | t], fun, acc) do
    case fun.(value) do
      {:ok, value} -> map(t, fun, Map.put(acc, key, value))
      :error -> :error
    end
  end

  defp map([], _fun, acc) do
    {:ok, acc}
  end

  defp map(_, _, _), do: :error

  defp to_i(nil), do: nil
  defp to_i(int) when is_integer(int), do: int
  defp to_i(bin) when is_binary(bin) do
    case Integer.parse(bin) do
      {int, ""} -> int
      _ -> nil
    end
  end
end
