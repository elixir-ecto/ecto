defmodule Ecto.Query.Normalizer do
  @moduledoc false

  # Normalizes a query so that it is as consistent as possible.

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr

  def normalize(Query[] = query, opts) do
    query |> auto_select(opts) |> setup_entities
  end

  # Auto select the entity in the from expression
  defp auto_select(Query[] = query, opts) do
    if !opts[:skip_select] && query.select == nil do
      var = { :&, [], [0] }
      query.select(QueryExpr[expr: var])
    else
      query
    end
  end

  # Adds all entities to the query for fast access
  defp setup_entities(Query[] = query) do
    entities = (if query.from, do: [query.from], else: []) ++
      Enum.map(query.joins, &(&1.expr |> elem(0)))
    query.entities(list_to_tuple(entities))
  end
end
