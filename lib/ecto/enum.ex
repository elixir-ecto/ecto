defmodule Ecto.Enum do
  @moduledoc """
  A custom type that maps atoms to strings.

  `Ecto.Enum` must be used whenever you want to keep atom values in a field.
  Since atoms cannot be persisted to the database, `Ecto.Enum` converts them
  to a string or an integer when writing to the database and converts them back
  to atoms when loading data. It can be used in your schemas as follows:

      field :status, Ecto.Enum, values: [:foo, :bar, :baz]

  or

      field :status, Ecto.Enum, values: [foo: 1, bar: 2, baz: 5]

  Composite types, such as `:array`, are also supported:

      field :roles, {:array, Ecto.Enum}, values: [:Author, :Editor, :Admin]

  `:values` must be a list of atoms or a keyword list. Values will be cast to
  atoms safely and only if the atom exists in the list (otherwise an error will
  be raised). Attempting to load any string/integer not represented by an atom
  in the list will be invalid.

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

      Ecto.Enum.values(EnumSchema, :my_enum)
      #=> [:foo, :bar, :baz]

  """

  use Ecto.ParameterizedType

  @impl true
  def type(params), do: params.type

  @impl true
  def init(opts) do
    values = Keyword.get(opts, :values, nil)

    {type, values} =
      cond do
        is_list(values) and Enum.all?(values, &is_atom/1) ->
          {:string, Enum.map(values, fn atom -> {atom, to_string(atom)} end)}

        type = Keyword.keyword?(values) and infer_type(Keyword.values(values)) ->
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

    on_load = Map.new(values, fn {key, val} -> {val, key} end)
    on_dump = Enum.into(values, %{})
    %{on_load: on_load, on_dump: on_dump, values: Keyword.keys(values), type: type}
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
      schema.__changeset__()
    rescue
      _ in UndefinedFunctionError -> raise ArgumentError, "#{inspect schema} is not an Ecto schema"
    else
      %{^field => {:parameterized, Ecto.Enum, %{values: values}}} -> values
      %{^field => {_, {:parameterized, Ecto.Enum, %{values: values}}}} -> values
      %{} -> raise ArgumentError, "#{field} is not an Ecto.Enum field"
    end
  end
end
