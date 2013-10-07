defmodule Ecto.Query.Normalizer do
  @moduledoc false

  # Normalizes a query so that it is as consistent as possible.

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.AssocJoinExpr
  alias Ecto.Query.JoinExpr
  alias Ecto.Query.Util
  alias Ecto.Reflections.BelongsTo

  def normalize(Query[] = query, opts) do
    query |> auto_select(opts) |> setup_models
  end

  # Transform an assocation join to an ordinary join
  def normalize_join(AssocJoinExpr[] = join, Query[] = query) do
    { :., _, [left, right] } = join.expr
    model = Util.find_model(query.models, left)
    entity = model.__model__(:entity)
    refl = entity.__entity__(:association, right)
    associated = refl.associated

    assoc_var = Util.model_var(query, associated)
    pk = refl.primary_key
    fk = refl.foreign_key
    on_expr = on_expr(refl, assoc_var, fk, pk)
    on = QueryExpr[expr: on_expr, file: join.file, line: join.line]

    JoinExpr[qual: join.qual, model: associated, on: on, file: join.file, line: join.line]
  end

  def normalize_join(JoinExpr[] = expr, _query), do: expr

  def normalize_select(QueryExpr[expr: { :assoc, _, [fst, snd] }] = expr) do
    expr.expr({ :{}, [], [fst, snd] })
  end

  def normalize_select(QueryExpr[expr: _] = expr), do: expr

  defp on_expr(BelongsTo[], assoc_var, fk, pk) do
    quote do unquote(assoc_var).unquote(pk) == &0.unquote(fk) end
  end

  defp on_expr(_refl, assoc_var, fk, pk) do
    quote do unquote(assoc_var).unquote(fk) == &0.unquote(pk) end
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

  # Adds all models to the query for fast access
  defp setup_models(Query[] = query) do
    froms = if query.from, do: [query.from], else: []

    models = Enum.reduce(query.joins, froms, fn join, acc ->
      case join do
        AssocJoinExpr[expr: { :., _, [left, right] }] ->
          model = Util.find_model(Enum.reverse(acc), left)
          entity = model.__model__(:entity)
          refl = entity.__entity__(:association, right)
          assoc = if refl, do: refl.associated
          [assoc|acc]
        JoinExpr[model: model] ->
          [model|acc]
      end
    end)

    models |> Enum.reverse |> list_to_tuple |> query.models
  end
end
