defmodule Ecto.Associations do
  @moduledoc false

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util

  def normalize(QueryExpr[expr: { _ , _ }] = expr, _query), do: expr

  def normalize(QueryExpr[expr: { :., _, [left, right] }] = expr, Query[] = query) do
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
end
