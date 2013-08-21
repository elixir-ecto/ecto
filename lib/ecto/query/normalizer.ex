defmodule Ecto.Query.Normalizer do
  @moduledoc false

  # Normalizes a query so that it is as consistent as possible.

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util

  def normalize(Query[] = query, opts) do
    query |> auto_select(opts) |> setup_entities
  end

  def normalize_join(QueryExpr[expr: { _ , _ }] = expr, _query), do: expr

  def normalize_join(QueryExpr[expr: { :., _, [left, right] }] = expr, Query[] = query) do
    entity = Util.find_entity(query.entities, left)
    refl = entity.__ecto__(:association, right)
    associated = refl.associated
    from = Util.from_entity_var(query)

    assoc_var = Util.entity_var(query, associated)
    pk = query.from.__ecto__(:primary_key)
    fk = refl.foreign_key

    on_expr = quote do unquote(assoc_var).unquote(fk) == unquote(from).unquote(pk) end
    on = QueryExpr[expr: on_expr]
    expr.expr({ associated, on })
  end

  def normalize_select(QueryExpr[expr: { :assoc, _, [fst, snd] }] = expr) do
    expr.expr({ fst, snd })
  end

  def normalize_select(QueryExpr[expr: _] = expr), do: expr

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
