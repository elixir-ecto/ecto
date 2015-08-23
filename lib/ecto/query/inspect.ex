defimpl Inspect, for: Ecto.Query do
  import Inspect.Algebra
  alias Ecto.Query.JoinExpr

  @doc false
  def inspect(query, opts) do
    list = Enum.map(to_list(query), fn
      {key, string} ->
        concat(Atom.to_string(key) <> ": ", string)
      string ->
        string
    end)

    surround_many("#Ecto.Query<", list, ">", opts, fn str, _ -> str end)
  end

  @doc false
  def to_string(query) do
    Enum.map_join(to_list(query), ",\n  ", fn
      {key, string} ->
        Atom.to_string(key) <> ": " <> string
      string ->
        string
    end)
  end

  defp to_list(query) do
    names =
      query
      |> collect_sources
      |> generate_letters
      |> generate_names
      |> List.to_tuple

    from      = bound_from(query.from, elem(names, 0))
    joins     = joins(query.joins, names)
    preloads  = preloads(query.preloads)
    assocs    = assocs(query.assocs, names)

    wheres    = kw_exprs(:where, query.wheres, names)
    group_bys = kw_exprs(:group_by, query.group_bys, names)
    havings   = kw_exprs(:having, query.havings, names)
    order_bys = kw_exprs(:order_by, query.order_bys, names)
    updates   = kw_exprs(:update, query.updates, names)

    lock      = kw_inspect(:lock, query.lock)
    limit     = kw_expr(:limit, query.limit, names)
    offset    = kw_expr(:offset, query.offset, names)
    select    = kw_expr(:select, query.select, names)
    distinct  = kw_expr(:distinct, query.distinct, names)

    Enum.concat [from, joins, wheres, group_bys, havings, order_bys,
                 limit, offset, lock, distinct, updates, select, preloads, assocs]
  end

  defp bound_from(from, name), do: ["from #{name} in #{unbound_from from}"]

  defp unbound_from(nil),           do: "query"
  defp unbound_from({source, nil}), do: inspect source
  defp unbound_from({nil, model}),  do: inspect model
  defp unbound_from(from = {source, model}) do
    inspect if(source == model.__schema__(:source), do: model, else: from)
  end

  defp joins(joins, names) do
    joins
    |> Enum.with_index
    |> Enum.flat_map(fn {expr, ix} -> join(expr, elem(names, expr.ix || ix + 1), names) end)
  end

  defp join(%JoinExpr{qual: qual, assoc: {ix, right}}, name, names) do
    string = "#{name} in assoc(#{elem(names, ix)}, #{inspect right})"
    [{join_qual(qual), string}]
  end

  defp join(%JoinExpr{qual: qual, source: {source, model}, on: on}, name, names) do
    string = "#{name} in #{unbound_from {source, model}}"
    [{join_qual(qual), string}, on: expr(on, names)]
  end

  defp join(%JoinExpr{qual: qual, source: source, params: params, on: on}, name, names) do
    string = "#{name} in #{expr(source, names, params)}"
    [{join_qual(qual), string}, on: expr(on, names)]
  end

  defp preloads([]),       do: []
  defp preloads(preloads), do: [preload: inspect(preloads)]

  defp assocs([], _names),    do: []
  defp assocs(assocs, names), do: [preload: expr(assocs(assocs), names, %{})]

  defp assocs(assocs) do
    Enum.map assocs, fn
      {field, {idx, []}} ->
        {field, {:&, [], [idx]}}
      {field, {idx, children}} ->
        {field, {{:&, [], [idx]}, assocs(children)}}
    end
  end

  defp kw_exprs(key, exprs, names) do
    Enum.map exprs, &{key, expr(&1, names)}
  end

  defp kw_expr(_key, nil, _names), do: []
  defp kw_expr(key, expr, names),  do: [{key, expr(expr, names)}]

  defp kw_inspect(_key, nil), do: []
  defp kw_inspect(key, val),  do: [{key, inspect(val)}]

  defp expr(%{expr: expr, params: params}, names) do
    expr(expr, names, params)
  end

  defp expr(expr, names, params) do
    Macro.to_string(expr, &expr_to_string(&1, &2, names, params))
  end

  # For keyword and interpolated fragments use normal escaping
  defp expr_to_string({:fragment, _, [{_, _}|_] = parts}, _, names, params) do
    "fragment(" <> unmerge_fragments(parts, "", [], names, params) <> ")"
  end

  # Convert variables to proper names
  defp expr_to_string({:&, _, [ix]}, _, names, _) do
    elem(names, ix)
  end

  # Inject the interpolated value
  #
  # In case the query had its parameters removed,
  # we use ... to express the interpolated code.
  defp expr_to_string({:^, _, [_ix, _len]}, _, _, _params) do
    Macro.to_string {:^, [], [{:..., [], nil}]}
  end

  defp expr_to_string({:^, _, [ix]}, _, _, params) do
    escaped =
      case Enum.at(params || [], ix) do
        {value, _type} -> Macro.escape(value)
        _              -> {:..., [], nil}
      end
    Macro.to_string {:^, [], [escaped]}
  end

  # Strip trailing ()
  defp expr_to_string({{:., _, [_, _]}, _, []}, string, _, _) do
    size = byte_size(string)
    :binary.part(string, 0, size - 2)
  end

  # Tagged values
  defp expr_to_string(%Ecto.Query.Tagged{value: value, tag: nil}, _, _names, _params) do
    inspect value
  end

  defp expr_to_string(%Ecto.Query.Tagged{value: value, tag: tag}, _, names, params) do
    {:type, [], [value, tag]} |> expr(names, params)
  end

  defp expr_to_string(_expr, string, _, _) do
    string
  end

  defp unmerge_fragments([{:raw, s}, {:expr, v}|t], frag, args, names, params) do
    unmerge_fragments(t, frag <> s <> "?", [expr(v, names, params)|args], names, params)
  end

  defp unmerge_fragments([{:raw, s}], frag, args, _names, _params) do
    Enum.join [inspect(frag <> s)|Enum.reverse(args)], ", "
  end

  defp join_qual(:inner), do: :join
  defp join_qual(:left),  do: :left_join
  defp join_qual(:right), do: :right_join
  defp join_qual(:full),  do: :full_join

  defp collect_sources(query) do
    from_sources(query.from) ++ join_sources(query.joins)
  end

  defp from_sources({source, model}), do: [model || source]
  defp from_sources(nil),             do: ["query"]

  defp join_sources(joins) do
    Enum.map(joins, fn
      %JoinExpr{assoc: {_var, assoc}} ->
        assoc
      %JoinExpr{source: {source, model}} ->
        model || source
      %JoinExpr{source: {:fragment, _, _}} ->
        "fragment"
    end)
  end

  defp generate_letters(sources) do
    Enum.map(sources, fn source ->
      source
      |> Kernel.to_string
      |> normalize_source
      |> String.first
      |> String.downcase
    end)
  end

  defp generate_names(letters) do
    generate_names(Enum.reverse(letters), [], [])
  end

  defp generate_names([letter|rest], acc, found) do
    index = Enum.count(rest, & &1 == letter)

    cond do
      index > 0 ->
        generate_names(rest, ["#{letter}#{index}"|acc], [letter|found])
      letter in found ->
        generate_names(rest, ["#{letter}0"|acc], [letter|found])
      true ->
        generate_names(rest, [letter|acc], found)
    end
  end

  defp generate_names([], acc, _found) do
    acc
  end

  defp normalize_source("Elixir." <> _ = source),
    do: source |> Module.split |> List.last
  defp normalize_source(source),
    do: source
end
