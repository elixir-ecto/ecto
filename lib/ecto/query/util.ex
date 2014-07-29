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
  @doc false
  def value_to_type(value, fun \\ nil)

  def value_to_type(nil, _fun), do: {:ok, nil}
  def value_to_type(value, _fun) when is_boolean(value), do: {:ok, :boolean}
  def value_to_type(value, _fun) when is_binary(value), do: {:ok, :string}
  def value_to_type(value, _fun) when is_integer(value), do: {:ok, :integer}
  def value_to_type(value, _fun) when is_float(value), do: {:ok, :float}
  def value_to_type(%Decimal{}, _fun), do: {:ok, :decimal}

  def value_to_type(%Ecto.DateTime{} = dt, fun) do
    values = Map.delete(dt, :__struct__) |> Map.values
    types = Enum.map(values, &value_to_type(&1, fun))

    res = Enum.find_value(types, fn
      {:ok, :integer} -> nil
      {:error, _} = err -> err
      {:error, "all datetime elements have to be a literal of integer type"}
    end)

    res || {:ok, :datetime}
  end

  def value_to_type(%Ecto.Date{} = d, fun) do
    values = Map.delete(d, :__struct__) |> Map.values
    types = Enum.map(values, &value_to_type(&1, fun))

    res = Enum.find_value(types, fn
      {:ok, :integer} -> nil
      {:error, _} = err -> err
      {:error, "all date elements have to be a literal of integer type"}
    end)

    res || {:ok, :date}
  end

  def value_to_type(%Ecto.Time{} = t, fun) do
    values = Map.delete(t, :__struct__) |> Map.values
    types = Enum.map(values, &value_to_type(&1, fun))

    res = Enum.find_value(types, fn
      {:ok, :integer} -> nil
      {:error, _} = err -> err
      {:error, "all time elements have to be a literal of integer type"}
    end)

    res || {:ok, :time}
  end

  def value_to_type(%Ecto.Interval{} = dt, fun) do
    values = Map.delete(dt, :__struct__) |> Map.values
    types = Enum.map(values, &value_to_type(&1, fun))

    res = Enum.find_value(types, fn
      {:ok, :integer} -> nil
      {:error, _} = err -> err
      _ -> {:error, "all interval elements have to be a literal of integer type"}
    end)

    if res do
      res
    else
      {:ok, :interval}
    end
  end

  def value_to_type(%Ecto.Binary{value: binary}, fun) do
    case value_to_type(binary, fun) do
      {:ok, :binary} -> {:ok, :binary}
      {:ok, :string} -> {:ok, :binary}
      {:error, _} = err -> err
      _ -> {:error, "binary/1 argument has to be a literal of binary type"}
    end
  end

  def value_to_type(%Ecto.Array{value: list, type: type}, fun) do
    unless type in types or (list == [] and nil?(type)) do
      {:error, "invalid type given to `array/2`: `#{inspect type}`"}
    end

    elem_types = Enum.map(list, &value_to_type(&1, fun))

    res = Enum.find_value(elem_types, fn
      {:ok, elem_type} ->
        unless type_eq?(type, elem_type) do
          {:error, "all elements in array have to be of same type"}
        end
      {:error, _} = err ->
        err
    end)

    if res do
      res
    else
      {:ok, {:array, type}}
    end
  end

  def value_to_type(value, nil), do: {:error, "`unknown type of value `#{inspect value}`"}

  def value_to_type(expr, fun), do: fun.(expr)

  # Returns true if value is a query literal
  @doc false
  def literal?(nil),                          do: true
  def literal?(value) when is_boolean(value), do: true
  def literal?(value) when is_binary(value),  do: true
  def literal?(value) when is_integer(value), do: true
  def literal?(value) when is_float(value),   do: true
  def literal?(%Decimal{}),                   do: true
  def literal?(%Ecto.DateTime{}),             do: true
  def literal?(%Ecto.Date{}),                 do: true
  def literal?(%Ecto.Time{}),                 do: true
  def literal?(%Ecto.Interval{}),             do: true
  def literal?(%Ecto.Binary{}),               do: true
  def literal?(%Ecto.Array{}),                do: true
  def literal?(_),                            do: false

  # Returns true if the two types are considered equal by the type system
  # Note that this does not consider casting
  @doc false
  def type_eq?(_, :any), do: true
  def type_eq?(:any, _), do: true
  def type_eq?({outer, inner1}, {outer, inner2}), do: type_eq?(inner1, inner2)
  def type_eq?(type, type), do: true
  def type_eq?(_, _), do: false

  # Returns true if another type can be casted to the given type
  @doc false
  def type_castable_to?(:binary), do: true
  def type_castable_to?({:array, _}), do: true
  def type_castable_to?(_), do: false

  # Tries to cast the given value to the specified type.
  # If value cannot be casted just return it.
  @doc false
  def try_cast(binary, :binary) when is_binary(binary) do
    %Ecto.Binary{value: binary}
  end

  def try_cast(list, {:array, inner}) when is_list(list) do
    %Ecto.Array{value: list, type: inner}
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
