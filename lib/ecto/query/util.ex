defmodule Ecto.Query.Util do
  @moduledoc """
  This module provide utility functions on queries.
  """

  alias Ecto.Queryable
  alias Ecto.Query.Query

  @doc """
  Validates the query to check if it is correct. Should be called before
  compilation by the query adapter.
  """
  def validate(query, opts // []) do
    Ecto.Query.Validator.validate(query, opts)
  end

  @doc """
  Validates an update query to check if it is correct. Should be called before
  compilation by the query adapter.
  """
  def validate_update(query, binds, values) do
    Ecto.Query.Validator.validate_update(query, binds, values)
  end

  @doc """
  Validates a delete query to check if it is correct. Should be called before
  compilation by the query adapter.
  """
  def validate_delete(query) do
    Ecto.Query.Validator.validate_delete(query)
  end

  @doc """
  Validates a get query to check if it is correct. Should be called before
  compilation by the query adapter.
  """
  def validate_get(query) do
    Ecto.Query.Validator.validate_get(query)
  end

  @doc """
  Normalizes the query. Should be called before
  compilation by the query adapter.
  """
  def normalize(query, opts // []) do
    Ecto.Query.Normalizer.normalize(query, opts)
  end

  @doc """
  Merge a query expression's bindings with the bound vars from
  `from` expressions.
  """
  def merge_binding_vars(binding, vars) do
    Enum.zip(binding, vars)
  end

  # Merges a Queryable with a query expression
  @doc false
  def merge(queryable, type, expr) do
    query = Query[] = Queryable.to_query(queryable)
    check_merge(query, Query.new([{ type, expr }]))

    if type != :from and length(expr.binding) > length(query.froms) do
      raise Ecto.InvalidQuery, reason: "cannot bind more variables than there are from expressions"
    end

    case type do
      :from     -> query.update_froms(&(&1 ++ [expr]))
      :where    -> query.update_wheres(&(&1 ++ [expr]))
      :select   -> query.select(expr)
      :order_by -> query.update_order_bys(&(&1 ++ [expr]))
      :limit    -> query.limit(expr)
      :offset   -> query.offset(expr)
      :group_by -> query.update_group_bys(&(&1 ++ [expr]))
      :having   -> query.update_havings(&(&1 ++ [expr]))
    end
  end

  # Converts list of variables to list of atoms
  @doc false
  def escape_binding(binding) when is_list(binding) do
    vars = Enum.map(binding, &escape_var(&1))
    if var = Enum.filter(vars, &(&1 != :_)) |> not_uniq do
      raise Ecto.InvalidQuery, reason: "variable `#{var}` is already defined in query"
    end
    vars
  end

  def escape_binding(_) do
    raise Ecto.InvalidQuery, reason: "binding should be list of variables"
  end

  # Converts internal type format to "typespec" format
  @doc false
  def type_to_ast({ type, inner }), do: { type, [], [type_to_ast(inner)] }
  def type_to_ast(type) when is_atom(type), do: { type, [], nil }

  # Takes an elixir value an returns its ecto type
  @doc false
  def value_to_type(nil), do: nil
  def value_to_type(value) when is_boolean(value), do: :boolean
  def value_to_type(value) when is_binary(value), do: :string
  def value_to_type(value) when is_integer(value), do: :integer
  def value_to_type(value) when is_float(value), do: :float

  def value_to_type(list) when is_list(list) do
    types = Enum.map(list, &value_to_type/1)

    case types do
      [] ->
        { :list, :any }
      [type|rest] ->
        unless Enum.all?(rest, &type_eq?(type, &1)) do
          raise Ecto.InvalidQuery, reason: "all elements in list has to be of same type"
        end
        { :list, type }
    end
  end

  # Returns true if the two types are considered equal by the type system
  @doc false
  def type_eq?(_, :any), do: true
  def type_eq?(:any, _), do: true
  def type_eq?({ outer, inner1 }, { outer, inner2 }), do: type_eq?(inner1, inner2)
  def type_eq?(x, x), do: true
  def type_eq?(_, _), do: false

  defp escape_var(var) when is_atom(var) do
    var
  end

  defp escape_var({ var, _, context }) when is_atom(var) and is_atom(context) do
    var
  end

  defp escape_var(_) do
    raise Ecto.InvalidQuery, reason: "binding should be list of variables"
  end

  # Returns nil if all elements in the collection are unique or the first
  # non-unique element
  defp not_uniq(collection) do
    Enum.sort(collection) |> do_not_uniq
  end

  defp do_not_uniq([]), do: nil
  defp do_not_uniq([_]), do: nil

  defp do_not_uniq([x, y | rest]) do
    if x == y, do: x, else: do_not_uniq([y|rest])
  end

  # Checks if a query merge can be done
  defp check_merge(Query[] = left, Query[] = right) do
    if left.select && right.select do
      raise Ecto.InvalidQuery, reason: "only one select expression is allowed in query"
    end

    if left.limit && right.limit do
      raise Ecto.InvalidQuery, reason: "only one limit expression is allowed in query"
    end

    if left.offset && right.offset do
      raise Ecto.InvalidQuery, reason: "only one offset expression is allowed in query"
    end
  end
end
