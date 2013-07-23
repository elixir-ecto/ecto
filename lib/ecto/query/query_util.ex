defmodule Ecto.Query.QueryUtil do
  @moduledoc """
  This module provide utility functions on queries.
  """

  alias Ecto.Query.Query

  @doc """
  Validates the query to check if it is correct. Should be called before
  compilation by the query adapter.
  """
  def validate(query) do
    Ecto.Query.Validator.validate(query)
  end

  @doc """
  Normalizes the query. Should be called before
  compilation by the query adapter.
  """
  def normalize(query) do
    Ecto.Query.Normalizer.normalize(query)
  end

  @doc """
  Merge a query expression's bindings with the bound vars from
  `from` expressions.
  """
  def merge_binding_vars(binding, vars) do
    Enum.zip(binding, vars)
  end

  # Merges two keyword queries
  @doc false
  def merge(Query[] = left, Query[] = right) do
    check_merge(left, right)

    Query[ froms:     left.froms ++ right.froms,
           wheres:    left.wheres ++ right.wheres,
           select:    right.select,
           order_bys: left.order_bys ++ right.order_bys,
           limit:     right.limit,
           offset:    right.offset ]
  end

  # Merges a keyword query with a query expression
  @doc false
  def merge(Query[] = query, type, expr) do
    check_merge(query, Query.new([{ type, expr }]))

    case type do
      :from     -> query.update_froms(&1 ++ [expr])
      :where    -> query.update_wheres(&1 ++ [expr])
      :select   -> query.select(expr)
      :order_by -> query.update_order_bys(&1 ++ [expr])
      :limit    -> query.limit(expr)
      :offset   -> query.offset(expr)
    end
  end

  # Checks if a keyword query merge can be done
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
