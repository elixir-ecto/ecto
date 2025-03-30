defmodule Ecto.Enum do
  @moduledoc """
  A custom type that maps atoms to strings or integers.

  `Ecto.Enum` must be used whenever you want to keep atom values in a field.
  Since atoms cannot be persisted to the database, `Ecto.Enum` converts them
  to strings or integers when writing to the database and converts them back
  to atoms when loading data. It can be used in your schemas as follows:

      # Stored as strings
      field :status, Ecto.Enum, values: [:foo, :bar, :baz]

  or

      # Stored as integers
      field :status, Ecto.Enum, values: [foo: 1, bar: 2, baz: 5]

  Therefore, the type to be used in your migrations for enum fields depends
  on the choice above. For the cases above, one would do, respectively:

      add :status, :string

  or

      add :status, :integer

  Some databases also support enum types, which you could use in combination
  with the above.

  Composite types, such as `:array`, are also supported which allow selecting
  multiple values per record:

      field :roles, {:array, Ecto.Enum}, values: [:author, :editor, :admin]

  Overall, `:values` must be a list of atoms or a keyword list. Values will be
  cast to atoms safely and only if the atom exists in the list (otherwise an
  error will be raised). Attempting to load any string/integer not represented
  by an atom in the list will be invalid.

  The helper function `mappings/2` returns the mappings for a given schema and
  field, which can be used in places like form drop-downs. See `mappings/2` for
  examples.

  If you want the values only, you can use `values/2`, and if you want
  the "dump-able" values only, you can use `dump_values/2`.

  ## Embeds

  `Ecto.Enum` allows to customize how fields are dumped within embeds through the
  `:embed_as` option. Two alternatives are supported: `:values`, which will save
  the enum keys (and not their respective mapping), and `:dumped`, which will save
  the dumped value. The default is `:values`. For example, assuming the following
  schema:

      defmodule EnumSchema do
        use Ecto.Schema

        schema "my_schema" do
          embeds_one :embed, Embed do
            field :embed_as_values, Ecto.Enum, values: [foo: 1, bar: 2], embed_as: :values
            field :embed_as_dump, Ecto.Enum, values: [foo: 1, bar: 2], embed_as: :dumped
          end
        end
      end

  The `:embed_as_values` field value will save `:foo` or `:bar`, while the
  `:embed_as_dump` field value will save `1` or `2`.
  """

  use Ecto.ParameterizedType

  @impl true
  def type(params), do: params.type

  @impl true
  def init(opts) do
    values = opts[:values]

    {type, mappings} =
      cond do
        is_list(values) and Enum.all?(values, &is_atom/1) ->
          validate_unique!(values)
          {:string, Enum.map(values, fn atom -> {atom, to_string(atom)} end)}

        type = Keyword.keyword?(values) and infer_type(Keyword.values(values)) ->
          validate_unique!(Keyword.keys(values))
          validate_unique!(Keyword.values(values))
          {type, values}

        true ->
          raise ArgumentError, """
          Ecto.Enum types must have a values option specified as a list of atoms or a
          keyword list with a mapping from atoms to either integer or string values.

          For example:

              field :my_field, Ecto.Enum, values: [:foo, :bar]

          or

              field :my_field, Ecto.Enum, values: [foo: 1, bar: 2, baz: 5]
          """
      end

    on_load = Map.new(mappings, fn {key, val} -> {val, key} end)
    on_dump = Map.new(mappings)
    on_cast = Map.new(mappings, fn {key, _} -> {Atom.to_string(key), key} end)

    embed_as =
      case Keyword.get(opts, :embed_as, :values) do
        :values ->
          :self

        :dumped ->
          :dump

        other ->
          raise ArgumentError, """
          the `:embed_as` option for `Ecto.Enum` accepts either `:values` or `:dumped`,
          received: `#{inspect(other)}`
          """
      end

    %{
      on_load: on_load,
      on_dump: on_dump,
      on_cast: on_cast,
      mappings: mappings,
      embed_as: embed_as,
      type: type
    }
  end

  defp validate_unique!(values) do
    if length(Enum.uniq(values)) != length(values) do
      raise ArgumentError, """
      Ecto.Enum type values must be unique.

      For example:

          field :my_field, Ecto.Enum, values: [:foo, :bar, :foo]

      is invalid, while

          field :my_field, Ecto.Enum, values: [:foo, :bar, :baz]

      is valid
      """
    end
  end

  defp infer_type(values) do
    cond do
      Enum.all?(values, &is_integer/1) -> :integer
      Enum.all?(values, &is_binary/1) -> :string
      true -> nil
    end
  end

  @impl true
  def cast(nil, _params), do: {:ok, nil}

  def cast(data, params) do
    case params do
      %{on_load: %{^data => as_atom}} ->
        {:ok, as_atom}

      %{on_dump: %{^data => _}} ->
        {:ok, data}

      %{on_cast: %{^data => as_atom}} ->
        {:ok, as_atom}

      params ->
        {:error, validation: :inclusion, enum: Map.keys(params.on_cast)}
    end
  end

  @impl true
  def load(nil, _, _), do: {:ok, nil}

  def load(data, _loader, %{on_load: on_load}) do
    case on_load do
      %{^data => as_atom} -> {:ok, as_atom}
      _ -> :error
    end
  end

  @impl true
  def dump(nil, _, _), do: {:ok, nil}

  def dump(data, _dumper, %{on_dump: on_dump}) do
    case on_dump do
      %{^data => as_string} -> {:ok, as_string}
      _ -> :error
    end
  end

  @impl true
  def equal?(a, b, _params), do: a == b

  @impl true
  def embed_as(_, %{embed_as: embed_as}), do: embed_as

  @impl true
  def format(%{mappings: mappings}) do
    "#Ecto.Enum<values: #{inspect(Keyword.keys(mappings))}>"
  end

  @doc """
  Returns the possible values for a given schema or types map and field.

  These values are the atoms that represent the different possible values
  of the field.

  ## Examples

  Assuming this schema:

      defmodule MySchema do
        use Ecto.Schema

        schema "my_schema" do
          field :my_string_enum, Ecto.Enum, values: [:foo, :bar, :baz]
          field :my_integer_enum, Ecto.Enum, values: [foo: 1, bar: 2, baz: 5]
        end
      end

  Then:

      Ecto.Enum.values(MySchema, :my_string_enum)
      #=> [:foo, :bar, :baz]

      Ecto.Enum.values(MySchema, :my_integer_enum)
      #=> [:foo, :bar, :baz]

  """
  @spec values(module | map, atom) :: [atom()]
  def values(schema_or_types, field) do
    schema_or_types
    |> mappings(field)
    |> Keyword.keys()
  end

  @doc """
  Returns the possible dump values for a given schema or types map and field

  "Dump values" are the values that can be dumped in the database. For enums stored
  as strings, these are the strings that will be dumped in the database. For enums
  stored as integers, these are the integers that will be dumped in the database.

  ## Examples

  Assuming this schema:

      defmodule MySchema do
        use Ecto.Schema

        schema "my_schema" do
          field :my_string_enum, Ecto.Enum, values: [:foo, :bar, :baz]
          field :my_integer_enum, Ecto.Enum, values: [foo: 1, bar: 2, baz: 5]
        end
      end

  Then:

      Ecto.Enum.dump_values(MySchema, :my_string_enum)
      #=> ["foo", "bar", "baz"]

      Ecto.Enum.dump_values(MySchema, :my_integer_enum)
      #=> [1, 2, 5]

  `schema_or_types` can also be a types map. See `mappings/2` for more information.
  """
  @spec dump_values(module | map, atom) :: [String.t()] | [integer()]
  def dump_values(schema_or_types, field) do
    schema_or_types
    |> mappings(field)
    |> Keyword.values()
  end

  @doc """
  Casts a value from the given `schema` and `field`.

  ## Examples

  Assuming this schema:

      defmodule MySchema do
        use Ecto.Schema

        schema "my_schema" do
          field :my_string_enum, Ecto.Enum, values: [:foo, :bar, :baz]
          field :my_integer_enum, Ecto.Enum, values: [foo: 1, bar: 2, baz: 5]
        end
      end

  Then:

      Ecto.Enum.cast_value(MySchema, :my_string_enum, "foo")
      #=> {:ok, :foo}

      Ecto.Enum.cast_value(MySchema, :my_string_enum, :foo)
      #=> {:ok, :foo}

      Ecto.Enum.cast_value(MySchema, :my_string_enum, "qux")
      #=> :error

      Ecto.Enum.cast_value(MySchema, :my_integer_enum, 1)
      #=> {:ok, :foo}

      Ecto.Enum.cast_value(MySchema, :my_integer_enum, :foo)
      #=> {:ok, :foo}

      Ecto.Enum.cast_value(MySchema, :my_integer_enum, 6)
      #=> :error

  `schema_or_types` can also be a types map. See `mappings/2` for more information.
  """
  @spec cast_value(module | map, atom, binary | atom | integer) :: {:ok, atom} | :error
  def cast_value(schema_or_types, field, value) do
    params = get_params(schema_or_types, field)
    case cast(value, params) do
      {:ok, casted_value} -> {:ok, casted_value}
      {:error, _reason} -> :error
    end
  end

  @doc """
  Returns the mappings between values and dumped values.

  ## Examples

  Assuming this schema:

      defmodule MySchema do
        use Ecto.Schema

        schema "my_schema" do
          field :my_string_enum, Ecto.Enum, values: [:foo, :bar, :baz]
          field :my_integer_enum, Ecto.Enum, values: [foo: 1, bar: 2, baz: 5]
        end
      end

  Here are some examples of using `mappings/2` with it:

      Ecto.Enum.mappings(MySchema, :my_string_enum)
      #=> [foo: "foo", bar: "bar", baz: "baz"]

      Ecto.Enum.mappings(MySchema, :my_integer_enum)
      #=> [foo: 1, bar: 2, baz: 5]

  Examples of calling `mappings/2` with a types map:

      schemaless_types = %{
        my_enum: Ecto.ParameterizedType.init(Ecto.Enum, values: [:foo, :bar, :baz]),
        my_integer_enum: Ecto.ParameterizedType.init(Ecto.Enum, values: [foo: 1, bar: 2, baz: 5])
      }

      Ecto.Enum.mappings(schemaless_types, :my_enum)
      #=> [foo: "foo", bar: "bar", baz: "baz"]
      Ecto.Enum.mappings(schemaless_types, :my_integer_enum)
      #=> [foo: 1, bar: 2, baz: 5]

  """
  @spec mappings(module | map, atom) :: keyword(String.t() | integer())
  def mappings(schema_or_types, field) do
    get_params(schema_or_types, field)
    |> Map.fetch!(:mappings)
  end

  defp get_params(schema_or_types, field)

  defp get_params(schema, field) when is_atom(schema) do
    try do
      schema.__changeset__()
    rescue
      _ in UndefinedFunctionError ->
        raise ArgumentError, "#{inspect(schema)} is not an Ecto schema or types map"
    else
      %{} = types -> get_params(types, field)
    end
  end

  defp get_params(types, field) when is_map(types) do
    case types do
      %{^field => {:parameterized, {Ecto.Enum, params}}} -> params
      %{^field => {_, {:parameterized, {Ecto.Enum, params}}}} -> params
      %{^field => _} -> raise ArgumentError, "#{field} is not an Ecto.Enum field"
      %{} -> raise ArgumentError, "#{field} does not exist"
    end
  end
end
