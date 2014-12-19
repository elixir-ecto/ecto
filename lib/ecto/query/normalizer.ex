defmodule Ecto.Query.Normalizer do
  @moduledoc false

  # Normalizes a query so that it is as consistent as possible.

  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr

  def normalize(query, opts \\ []) do
    query
    |> normalize_sources
    |> auto_select(opts)
  end

  # Normalize all sources and adds a source
  # field to the query for fast access.
  defp normalize_sources(query) do
    from = query.from || error!("query must have a from expression")

    {joins, sources} =
      Enum.map_reduce(query.joins, [from], &normalize_join(&1, &2, query))

    %{query | sources: sources |> Enum.reverse |> List.to_tuple, joins: joins}
  end

  defp normalize_join(%JoinExpr{assoc: {ix, assoc}} = join, sources, query) do
    {_, model} = Enum.fetch!(Enum.reverse(sources), ix)

    unless model do
      error! query, join, "association join cannot be performed without a model"
    end

    refl = model.__schema__(:association, assoc)

    unless refl do
      error! query, join, "could not find association `#{assoc}` on model #{inspect model}"
    end

    associated = refl.associated
    source     = {associated.__schema__(:source), associated}

    on_expr    = on_expr(join.on, refl, ix, length(sources))
    on         = %QueryExpr{expr: on_expr, file: join.file, line: join.line}
    {%{join | source: source, on: on}, [source|sources]}
  end

  defp normalize_join(%JoinExpr{source: {source, nil}} = join, sources, _query) when is_binary(source) do
    source = {source, nil}
    {%{join | source: source}, [source|sources]}
  end

  defp normalize_join(%JoinExpr{source: {nil, model}} = join, sources, _query) when is_atom(model) do
    source = {model.__schema__(:source), model}
    {%{join | source: source}, [source|sources]}
  end

  defp on_expr(on_expr, refl, var_ix, assoc_ix) do
    key = refl.key
    var = {:&, [], [var_ix]}
    assoc_key = refl.assoc_key
    assoc_var = {:&, [], [assoc_ix]}

    relation = quote do
      unquote(assoc_var).unquote(assoc_key) == unquote(var).unquote(key)
    end

    if on_expr do
      quote do: unquote(on_expr.expr) and unquote(relation)
    else
      relation
    end
  end

  # Auto select the model in the from expression
  defp auto_select(query, opts) do
    if !opts[:skip_select] && query.select == nil do
      var = {:&, [], [0]}
      %{query | select: %QueryExpr{expr: var}}
    else
      query
    end
  end

  defp error!(message) do
    raise Ecto.QueryError, message: message
  end

  defp error!(query, expr, message) do
    raise Ecto.QueryError, message: message, query: query, file: expr.file, line: expr.line
  end
end
