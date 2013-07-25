defmodule Ecto.Query.QueryUtil do
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
      :from     -> query.update_froms(&1 ++ [expr])
      :where    -> query.update_wheres(&1 ++ [expr])
      :select   -> query.select(expr)
      :order_by -> query.update_order_bys(&1 ++ [expr])
      :limit    -> query.limit(expr)
      :offset   -> query.offset(expr)
    end
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
