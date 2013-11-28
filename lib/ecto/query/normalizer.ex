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
    query
    |> setup_sources
    |> auto_select(opts)
    |> normalize_group_by
  end

  # Transform an assocation join to an ordinary join
  def normalize_join(AssocJoinExpr[] = join, Query[] = query) do
    { :., _, [left, right] } = join.expr
    entity = Util.find_source(query.sources, left) |> Util.entity
    refl = entity.__entity__(:association, right)
    associated = refl.associated

    assoc_var = Util.model_var(query, associated)
    pk = refl.primary_key
    fk = refl.foreign_key
    on_expr = on_expr(refl, assoc_var, fk, pk)
    on = QueryExpr[expr: on_expr, file: join.file, line: join.line]

    JoinExpr[qual: join.qual, source: associated, on: on, file: join.file, line: join.line]
  end

  def normalize_join(JoinExpr[] = expr, _query), do: expr

  def normalize_select(QueryExpr[expr: { :assoc, _, [fst, snd] }] = expr) do
    expr.expr({ :{}, [], [fst, snd] })
  end

  def normalize_select(QueryExpr[expr: _] = expr), do: expr

  def normalize_preload(fields) do
    Enum.map(List.wrap(fields), fn
      { field, sub_fields } -> { field, normalize_preload(sub_fields) }
      field -> { field, [] }
    end)
  end

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

  # Group by all fields
  defp normalize_group_by(Query[] = query) do
    Enum.map(query.group_bys, fn
      QueryExpr[expr: { :&, _, _ } = var] = expr ->
        entity = Util.find_source(query.sources, var) |> Util.entity
        fields = entity.__entity__(:field_names)
        expr.expr(Enum.map(fields, &{ var, &1 }))
      field ->
        field
    end) |> query.group_bys
  end

  # Adds all sources to the query for fast access
  defp setup_sources(Query[] = query) do
    froms = if query.from, do: [query.from], else: []

    sources = Enum.reduce(query.joins, froms, fn
      AssocJoinExpr[expr: { :., _, [left, right] }], acc ->
        entity = Util.find_source(Enum.reverse(acc), left) |> Util.entity

        if entity && (refl = entity.__entity__(:association, right)) do
          assoc = refl.associated
          [ { assoc.__model__(:source), assoc.__model__(:entity), assoc } | acc ]
        else
          [nil|acc]
        end

      JoinExpr[source: source], acc when is_binary(source) ->
        [ { source, nil, nil } | acc ]

      JoinExpr[source: model], acc when is_atom(model) ->
        [ { model.__model__(:source), model.__model__(:entity), model } | acc ]
    end)

    sources |> Enum.reverse |> list_to_tuple |> query.sources
  end
end
