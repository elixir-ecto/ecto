defmodule Ecto.Query.Util do
  @moduledoc """
  This module provide utility functions on queries.
  """

  alias Ecto.Query.Query

  @doc """
  Validates the query to check if it is correct. Should be called before
  compilation by the query adapter.
  """
  def validate(query, query_apis, opts // []) do
    Ecto.Query.Validator.validate(query, query_apis, opts)
  end

  @doc """
  Validates an update query to check if it is correct. Should be called before
  compilation by the query adapter.
  """
  def validate_update(query, query_apis, values) do
    Ecto.Query.Validator.validate_update(query, query_apis, values)
  end

  @doc """
  Validates a delete query to check if it is correct. Should be called before
  compilation by the query adapter.
  """
  def validate_delete(query, query_apis) do
    Ecto.Query.Validator.validate_delete(query, query_apis)
  end

  @doc """
  Validates a get query to check if it is correct. Should be called before
  compilation by the query adapter.
  """
  def validate_get(query, query_apis) do
    Ecto.Query.Validator.validate_get(query, query_apis)
  end

  @doc """
  Normalizes the query. Should be called before validation and compilation by
  the query adapter.
  """
  def normalize(query, opts // []) do
    Ecto.Query.Normalizer.normalize(query, opts)
  end

  @doc """
  Look up a source with a variable.
  """
  def find_source(sources, { :&, _, [ix] }) when is_tuple(sources) do
    elem(sources, ix)
  end

  def find_source(sources, { :&, _, [ix] }) when is_list(sources) do
    Enum.at(sources, ix)
  end

  @doc """
  Look up the expression where the variable was bound.
  """
  def source_expr(Query[from: from], { :&, _, [0] }) do
    from
  end

  def source_expr(Query[joins: joins], { :&, _, [ix] }) do
    Enum.at(joins, ix - 1)
  end

  @doc "Returns the source from a source tuple."
  def source({ source, _entity, _model }), do: source

  @doc "Returns entity from a source tuple or nil if there is none."
  def entity({ _source, entity, _model }), do: entity

  @doc "Returns model from a source tuple or nil if there is none."
  def model({ _source, _entity, model }), do: model

  # Converts internal type format to "typespec" format
  @doc false
  def type_to_ast({ type, inner }), do: { type, [], [type_to_ast(inner)] }
  def type_to_ast(type) when is_atom(type), do: { type, [], nil }

  # Takes an elixir value an returns its ecto type
  @doc false
  def value_to_type(nil), do: { :ok, nil }
  def value_to_type(value) when is_boolean(value), do: { :ok, :boolean }
  def value_to_type(value) when is_binary(value), do: { :ok, :string }
  def value_to_type(value) when is_integer(value), do: { :ok, :integer }
  def value_to_type(value) when is_float(value), do: { :ok, :float }

  def value_to_type(Ecto.DateTime[] = dt) do
    valid = is_integer(dt.year) and is_integer(dt.month) and is_integer(dt.day) and
            is_integer(dt.hour) and is_integer(dt.min)   and is_integer(dt.sec)

    if valid do
      { :ok, :datetime }
    else
      { :error, "all datetime elements has to be a literal of integer type" }
    end
  end

  def value_to_type(Ecto.Interval[] = dt) do
    valid = is_integer(dt.year) and is_integer(dt.month) and is_integer(dt.day) and
            is_integer(dt.hour) and is_integer(dt.min)   and is_integer(dt.sec)

    if valid do
      { :ok, :interval }
    else
      { :error, "all interval elements has to be a literal of integer type" }
    end
  end

  def value_to_type(Ecto.Binary[value: binary]) do
    if is_binary(binary) do
      { :ok, :binary }
    else
      { :error, "binary/1 argument has to be a literal of binary type" }
    end
  end

  def value_to_type(list) when is_list(list) do
    types = Enum.map(list, &value_to_type/1)

    if error = Enum.find(types, &match?({ :error, _ }, &1)) do
      error
    else
      types = Enum.map(types, &elem(&1, 1))

      case types do
        [] ->
          { :ok, { :list, :any } }
        [type|rest] ->
          if Enum.all?(rest, &type_eq?(type, &1)) do
            { :ok, { :list, type } }
          else
            { :error, "all elements in list has to be of same type" }
          end
      end
    end
  end

  def value_to_type(value), do: { :error, "`unknown type of value `#{inspect value}`" }

  # Returns true if the two types are considered equal by the type system
  @doc false
  def type_eq?(_, :any), do: true
  def type_eq?(:any, _), do: true
  def type_eq?({ outer, inner1 }, { outer, inner2 }), do: type_eq?(inner1, inner2)
  def type_eq?(x, x), do: true
  def type_eq?(_, _), do: false

  # Get var for given model in query
  def model_var(Query[] = query, model) do
    sources = tuple_to_list(query.sources)
    pos = Enum.find_index(sources, &(model(&1) == model))
    { :&, [], [pos] }
  end

  # Find var in select clause. Returns a list of tuple and list indicies to
  # find the var.
  def locate_var({ left, right }, var) do
    locate_var({ :{}, [], [left, right] }, var)
  end

  def locate_var({ :{}, _, list }, var) do
    locate_var(list, var)
  end

  def locate_var({ :assoc, _, [left, _right] }, var) do
    if left == var, do: []
  end

  def locate_var(list, var) when is_list(list) do
    list = Stream.with_index(list)
    res = Enum.find_value(list, fn { elem, ix } ->
      if poss = locate_var(elem, var) do
        { poss, ix }
      else
        nil
      end
    end)

    case res do
      { poss, pos } -> [pos|poss]
      nil -> nil
    end
  end

  def locate_var(expr, var) do
    if expr == var, do: []
  end
end
