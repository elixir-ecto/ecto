defmodule Ecto.Enum do
  @moduledoc """
  A custom type that maps atoms to strings.

  `Ecto.Enum` must be used whenever you want to keep atom values in a field.
  Since atoms cannot be persisted to the database, `Ecto.Enum` converts them
  to string when writing to the database and converts them back to atoms when
  loading data. It can be used in your schemas as follows:

      field :status, Ecto.Enum, values: [:foo, :bar, :baz]

  Composite types, such as `:array`, are also supported:

      field :roles, {:array, Ecto.Enum}, values: [:Author, :Editor, :Admin]

  `:values` must be a list of atoms. String values will be cast to atoms safely
  and only if the atom exists in the list (otherwise an error will be raised).
  Attempting to load any string not represented by an atom in the list will be
  invalid.

  The helper function `values/2` returns the values for a given schema and
  field, which can be used in places like form drop-downs. For example,
  given the following schema:

      defmodule EnumSchema do
        use Ecto.Schema

        schema "my_schema" do
          field :my_enum, Ecto.Enum, values: [:foo, :bar, :baz]
        end
      end

  you can call `values/2` like this:

      > Ecto.Enum.values(EnumSchema, :my_enum)
      [:foo, :bar, :baz]

  """

  use Ecto.ParameterizedType

  @impl true
  def type(_params), do: :string

  @impl true
  def init(opts) do
    values = Keyword.get(opts, :values, nil)

    unless is_list(values) and Enum.all?(values, &is_atom/1) do
      raise ArgumentError, """
      Ecto.Enum types must have a values option specified as a list of atoms. For example:

          field :my_field, Ecto.Enum, values: [:foo, :bar]
      """
    end

    on_load = Map.new(values, &{Atom.to_string(&1), &1})
    on_dump = Map.new(values, &{&1, Atom.to_string(&1)})
    %{on_load: on_load, on_dump: on_dump, values: values}
  end

  @impl true
  def cast(data, params) do
    case params do
      %{on_load: %{^data => as_atom}} -> {:ok, as_atom}
      %{on_dump: %{^data => _}} -> {:ok, data}
      _ -> :error
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
  def embed_as(_, _), do: :self

  def values(schema, field) do
    try do
      schema.__schema__(:type, field)
    rescue
      _ in UndefinedFunctionError -> raise ArgumentError, "#{inspect schema} is not an Ecto schema"
    else
      {:parameterized, Ecto.Enum, %{values: values}} -> values
      {_, {:parameterized, Ecto.Enum, %{values: values}}} -> values
      nil -> raise ArgumentError, "#{field} is not an Ecto.Enum field"
    end
  end
end
