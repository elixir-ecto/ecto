defmodule Ecto.Enum do
  @moduledoc """
  Ecto.Enum is used to safely store an atom field in Ecto.

    field "foo", Ecto.Enum, values: [:foo, :bar, :baz]

  `values:` must be a list of atoms. String values will be cast to atoms safely and only if the atom
  exists in the list (otherwise an error will be raised). Attempting to load any string not represented
  by an atom in the list of values will result in an error.

  """
  use Ecto.ParameterizedType

  def type(_params), do: :string

  def init(opts) do
    values = Keyword.get(opts, :values, nil)

    if !is_list(values) || !Enum.all?(values, &is_atom/1) do
      raise ArgumentError, "Ecto.Enum types must have a values option specified as a list of atoms, e.g. field :my_field, Ecto.Enum, values: [:foo, :bar]"
    end

    user_to_db = Map.new(values, &{&1, Atom.to_string(&1)})
    db_to_user = Map.new(values, &{Atom.to_string(&1), &1})
    %{user_to_db: user_to_db, db_to_user: db_to_user}
  end

  def cast(data, params) do
    case params do
      %{db_to_user: %{^data => as_atom}} -> {:ok, as_atom}
      %{user_to_db: %{^data => _}} -> {:ok, data}
      _ -> :error
    end
  end

  def load(nil, _, _), do: {:ok, nil}

  def load(data, _loader, %{db_to_user: db_to_user}) do
    case db_to_user do
      %{^data => as_atom} -> {:ok, as_atom}
      _ -> :error
    end
  end

  def dump(nil, _, _), do: {:ok, nil}

  def dump(data, _dumper, %{user_to_db: user_to_db}) do
    case user_to_db do
      %{^data => as_string} -> {:ok, as_string}
      _ -> :error
    end
  end

  def equal?(a, b, _params) do
    a == b
  end

  def embed_as(_, _) do
    :dump
  end
end
