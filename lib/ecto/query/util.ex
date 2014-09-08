defmodule Ecto.Query.Util do
  @moduledoc """
  This module provide utility functions on queries.
  """

  alias Ecto.Query

  @doc """
  Look up a source with a variable.
  """
  def find_source(sources, {:&, _, [ix]}) when is_tuple(sources) do
    elem(sources, ix)
  end

  def find_source(sources, {:&, _, [ix]}) when is_list(sources) do
    Enum.at(sources, ix)
  end

  @doc """
  Look up the expression where the variable was bound.
  """
  def source_expr(%Query{from: from}, {:&, _, [0]}) do
    from
  end

  def source_expr(%Query{joins: joins}, {:&, _, [ix]}) do
    Enum.at(joins, ix - 1)
  end

  @doc "Returns the source from a source tuple."
  def source({source, _model}), do: source

  @doc "Returns model from a source tuple or nil if there is none."
  def model({_source, model}), do: model

  # Converts internal type format to "typespec" format
  @doc false
  def type_to_ast({type, inner}), do: {type, [], [type_to_ast(inner)]}
  def type_to_ast(type) when is_atom(type), do: {type, [], nil}

  @doc false
  defmacro types do
    ~w(boolean string integer float decimal binary datetime date time interval virtual)a
  end

  @doc false
  defmacro poly_types do
    ~w(array)a
  end

  # Takes an elixir value and returns its ecto type
  # Only allows query literals
  @doc false
  def value_to_type(value)

  def value_to_type(nil), do: {:ok, :any}
  def value_to_type(value) when is_boolean(value), do: {:ok, :boolean}
  def value_to_type(value) when is_binary(value), do: {:ok, :string}
  def value_to_type(value) when is_integer(value), do: {:ok, :integer}
  def value_to_type(value) when is_float(value), do: {:ok, :float}

  def value_to_type(%Ecto.Tagged{value: binary, type: :binary}) do
    case value_to_type(binary) do
      {:ok, :binary}    -> {:ok, :binary}
      {:ok, :string}    -> {:ok, :binary}
      {:error, _} = err -> err
      _ ->
        {:error, "binary/1 argument has to be of binary type"}
    end
  end

  def value_to_type(%Ecto.Tagged{value: list, type: {:array, inner}}) do
    if inner in types or (list == [] and is_nil(inner)) do
      elem_types = Enum.map(list, &value_to_type/1)

      error =
        Enum.find_value(elem_types, fn
          {:ok, type} ->
            unless type_eq?(inner, type) or type_castable?(type, inner) do
              {:error, "all elements in array have to be of same type"}
            end
          {:error, _} = err ->
            err
        end)

      error || {:ok, {:array, inner}}
    else
      {:error, "invalid type given to `array/2`: `#{inspect inner}`"}
    end
  end

  def value_to_type(value), do: {:error, "unknown type of value `#{inspect value}`"}

  # Takes an elixir value and returns its ecto type.
  # Different to value_to_type/1 it also allows values
  # that can be interpolated into the query
  @doc false
  def external_to_type(%Decimal{}), do: {:ok, :decimal}

  def external_to_type(%Ecto.DateTime{} = dt) do
    values = Map.delete(dt, :__struct__) |> Map.values
    types = Enum.map(values, &external_to_type/1)

    res = Enum.find_value(types, fn
      {:ok, :integer} -> nil
      {:error, _} = err -> err
      {:error, "all datetime elements have to be of integer type"}
    end)

    res || {:ok, :datetime}
  end

  def external_to_type(%Ecto.Date{} = d) do
    values = Map.delete(d, :__struct__) |> Map.values
    types = Enum.map(values, &external_to_type/1)

    res = Enum.find_value(types, fn
      {:ok, :integer} -> nil
      {:error, _} = err -> err
      {:error, "all date elements have to be of integer type"}
    end)

    res || {:ok, :date}
  end

  def external_to_type(%Ecto.Time{} = t) do
    values = Map.delete(t, :__struct__) |> Map.values
    types = Enum.map(values, &external_to_type/1)

    res = Enum.find_value(types, fn
      {:ok, :integer} -> nil
      {:error, _} = err -> err
      {:error, "all time elements have to be of integer type"}
    end)

    res || {:ok, :time}
  end

  def external_to_type(%Ecto.Interval{} = dt) do
    values = Map.delete(dt, :__struct__) |> Map.values
    types = Enum.map(values, &external_to_type/1)

    res = Enum.find_value(types, fn
      {:ok, :integer} -> nil
      {:error, _} = err -> err
      _ -> {:error, "all interval elements have to be of integer type"}
    end)

    if res do
      res
    else
      {:ok, :interval}
    end
  end

  def external_to_type(value), do: value_to_type(value)

  # Returns true if the two types are considered equal by the type system
  # Note that this does not consider casting
  @doc false
  def type_eq?(_, :any), do: true
  def type_eq?(:any, _), do: true
  def type_eq?({outer, inner1}, {outer, inner2}), do: type_eq?(inner1, inner2)
  def type_eq?(type, type), do: true
  def type_eq?(_, _), do: false

  # Returns true if the literal type can be inferred as the second type.
  # A literal type is a type that does not require wrapping with
  # %Ecto.Tagged{}.
  @doc false
  def type_castable?(:string, :binary), do: true
  def type_castable?(_, _), do: false

  # Tries to cast the given value to the specified type.
  # If value cannot be casted just return it.
  @doc false
  def try_cast(binary, :binary) when is_binary(binary) do
    %Ecto.Tagged{value: binary, type: :binary}
  end

  def try_cast(list, {:array, inner}) when is_list(list) do
    %Ecto.Tagged{value: list, type: {:array, inner}}
  end

  def try_cast(value, _) do
    value
  end

  # Get var for given model in query
  def model_var(query, model) do
    sources = Tuple.to_list(query.sources)
    pos = Enum.find_index(sources, &(model(&1) == model))
    {:&, [], [pos]}
  end

  # Find var in select clause. Returns a list of tuple and list indicies to
  # find the var.
  def locate_var({left, right}, var) do
    locate_var({:{}, [], [left, right]}, var)
  end

  def locate_var({:{}, _, list}, var) do
    locate_var(list, var)
  end

  def locate_var({:assoc, _, [left, _right]}, var) do
    if left == var, do: []
  end

  def locate_var(list, var) when is_list(list) do
    list = Stream.with_index(list)
    res = Enum.find_value(list, fn {elem, ix} ->
      if poss = locate_var(elem, var) do
        {poss, ix}
      else
        nil
      end
    end)

    case res do
      {poss, pos} -> [pos|poss]
      nil -> nil
    end
  end

  def locate_var(expr, var) do
    if expr == var, do: []
  end
end
