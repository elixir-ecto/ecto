defmodule Ecto.Query.Normalizer do
  @moduledoc false

  # Normalizes a query so that it is as consistent as possible.

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util

  def normalize(Query[] = query, opts) do
    query |> auto_select(opts) |> setup_entities
  end

  def post_normalize(Query[] = query) do
    query.joins
      |> Enum.map(&Ecto.Associations.normalize(&1, query))
      |> query.joins
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
    froms = if query.from, do: [query.from], else: []

    entities = Enum.reduce(query.joins, froms, fn join, acc ->
      case join.expr do
        { entity, _ } ->
          [entity|acc]
        { :., _, [left, right] } ->
          entity = Util.find_entity(Enum.reverse(acc), left)
          refl = entity.__ecto__(:association, right)
          assoc = if refl, do: refl.associated
          [ assoc | acc ]
        entity ->
          [entity|acc]
      end
    end)

    entities |> Enum.reverse |> list_to_tuple |> query.entities
  end
end
