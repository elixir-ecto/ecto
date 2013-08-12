defmodule Ecto.Query.Normalizer do
  @moduledoc false

  # Normalizes a query to that it is as consistent as possible.
  # For now it only does auto-selecting.

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr

  def normalize(Query[] = query, opts) do
    if !opts[:skip_select] && query.select == nil do
      expr = { { :entity, :entity }, { :entity, [], nil } }
      query.select(QueryExpr[expr: expr, binding: [:entity]])
    else
      query
    end
  end
end
