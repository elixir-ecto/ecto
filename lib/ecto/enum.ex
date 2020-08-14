defmodule Ecto.Enum do
  @moduledoc """
  A custom type that maps atoms to strings.

  `Ecto.Enum` must be used whenever you want to keep atom values in a field.
  Since atoms cannot be persisted to the database, `Ecto.Enum` converts them
  to string when writing to the database and converts them back to atoms when
  loading data. It can be used in your schemas as follows:

      field :status, Ecto.Enum, values: [:foo, :bar, :baz]

  `:values` must be a list of atoms. String values will be cast to atoms safely
  and only if the atom exists in the list (otherwise an error will be raised).
  Attempting to load any string not represented by an atom in the list will be
  invalid.
  """

  use Ecto.ParameterizedType

  @impl Ecto.ParameterizedType
  def type(_params), do: :string

  @impl Ecto.ParameterizedType
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
    %{on_load: on_load, on_dump: on_dump}
  end

  @impl Ecto.ParameterizedType
  def change(_old_value, new_value, params) do
    case params do
      %{on_dump: %{^new_value => _}} -> {:ok, new_value, true}
      _ -> {:error, [message: "unknown enum value", value: new_value]}
   end
  end

  @impl Ecto.ParameterizedType
  def cast(data, params) do
    case params do
      %{on_load: %{^data => as_atom}} -> {:ok, as_atom}
      %{on_dump: %{^data => _}} -> {:ok, data}
      _ -> :error
    end
  end

  @impl Ecto.ParameterizedType
  def load(nil, _, _), do: {:ok, nil}

  def load(data, _loader, %{on_load: on_load}) do
    case on_load do
      %{^data => as_atom} -> {:ok, as_atom}
      _ -> :error
    end
  end

  @impl Ecto.ParameterizedType
  def dump(nil, _, _), do: {:ok, nil}

  def dump(data, _dumper, %{on_dump: on_dump}) do
    case on_dump do
      %{^data => as_string} -> {:ok, as_string}
      _ -> :error
    end
  end

  @impl Ecto.ParameterizedType
  def equal?(a, b, _params), do: a == b

  @impl Ecto.ParameterizedType
  def embed_as(_, _), do: :self
end
