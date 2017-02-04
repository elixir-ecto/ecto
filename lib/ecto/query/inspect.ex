import Inspect.Algebra
import Kernel, except: [to_string: 1]

alias Ecto.Query.{DynamicExpr, JoinExpr}

defimpl Inspect, for: Ecto.Query.DynamicExpr do
  def inspect(%DynamicExpr{binding: binding} = dynamic, opts) do
    {expr, binding, params, _, _} =
      Ecto.Query.Builder.Dynamic.fully_expand(%Ecto.Query{joins: Enum.drop(binding, 1)}, dynamic)
    names =
      for {name, _, _} <- binding, do: Atom.to_string(name)
    inspected =
      Inspect.Ecto.Query.expr(expr, List.to_tuple(names), %{expr: expr, params: params})

    surround_many("dynamic(", [Macro.to_string(binding), inspected], ")", opts, fn str, _ -> str end)
  end
end

defimpl Inspect, for: Ecto.Query do
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

    wheres    = bool_exprs(%{and: :where, or: :or_where}, query.wheres, names)
    group_bys = kw_exprs(:group_by, query.group_bys, names)
    havings   = bool_exprs(%{and: :having, or: :or_having}, query.havings, names)
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
  defp unbound_from({nil, schema}),  do: inspect schema
  defp unbound_from(from = {source, schema}) do
    inspect if source == schema.__schema__(:source), do: schema, else: from
  end
  defp unbound_from(%Ecto.SubQuery{query: query}) do
    "subquery(#{to_string query})"
  end
  defp unbound_from(%Ecto.Query{} = query) do
    "^" <> inspect(query)
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

  defp join(%JoinExpr{qual: qual, source: {:fragment, _, _} = source, on: on} = part, name, names) do
    string = "#{name} in #{expr(source, names, part)}"
    [{join_qual(qual), string}, on: expr(on, names)]
  end

  defp join(%JoinExpr{qual: qual, source: source, on: on}, name, names) do
    string = "#{name} in #{unbound_from source}"
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

  defp bool_exprs(keys, exprs, names) do
    Enum.map exprs, fn %{expr: expr, op: op} = part ->
      {Map.fetch!(keys, op), expr(expr, names, part)}
    end
  end

  defp kw_exprs(key, exprs, names) do
    Enum.map exprs, &{key, expr(&1, names)}
  end

  defp kw_expr(_key, nil, _names), do: []
  defp kw_expr(key, expr, names),  do: [{key, expr(expr, names)}]

  defp kw_inspect(_key, nil), do: []
  defp kw_inspect(key, val),  do: [{key, inspect(val)}]

  defp expr(%{expr: expr} = part, names) do
    expr(expr, names, part)
  end

  @doc false
  def expr(expr, names, part) do
    Macro.to_string(expr, &expr_to_string(&1, &2, names, part))
  end

  # For keyword and interpolated fragments use normal escaping
  defp expr_to_string({:fragment, _, [{_, _}|_] = parts}, _, names, part) do
    "fragment(" <> unmerge_fragments(parts, "", [], names, part) <> ")"
  end

  # Convert variables to proper names
  defp expr_to_string({:&, _, [ix]}, _, names, %{take: take}) do
    case take do
      %{^ix => {:any, fields}} when ix == 0 ->
        Kernel.inspect(fields)
      %{^ix => {tag, fields}} ->
        "#{tag}(" <> elem(names, ix) <> ", " <> Kernel.inspect(fields) <> ")"
      _ ->
        elem(names, ix)
    end
  end

  defp expr_to_string({:&, _, [ix]}, _, names, _) do
    try do
      elem(names, ix)
    rescue
      ArgumentError -> "unknown_binding!"
    end
  end

  # Inject the interpolated value
  #
  # In case the query had its parameters removed,
  # we use ... to express the interpolated code.
  defp expr_to_string({:^, _, [_ix, _len]}, _, _, _part) do
    Macro.to_string {:^, [], [{:..., [], nil}]}
  end

  defp expr_to_string({:^, _, [ix]}, _, _, %{params: params}) do
    case Enum.at(params || [], ix) do
      {value, _type} -> "^" <> Kernel.inspect(value, charlists: :as_lists)
      _              -> "^..."
    end
  end

  # Strip trailing ()
  defp expr_to_string({{:., _, [_, _]}, _, []}, string, _, _) do
    size = byte_size(string)
    :binary.part(string, 0, size - 2)
  end

  # Tagged values
  defp expr_to_string(%Ecto.Query.Tagged{value: value, tag: nil}, _, _names, _) do
    inspect value
  end

  defp expr_to_string(%Ecto.Query.Tagged{value: value, tag: tag}, _, names, part) do
    {:type, [], [value, tag]} |> expr(names, part)
  end

  defp expr_to_string(_expr, string, _, _) do
    string
  end

  defp unmerge_fragments([{:raw, s}, {:expr, v}|t], frag, args, names, part) do
    unmerge_fragments(t, frag <> s <> "?", [expr(v, names, part)|args], names, part)
  end

  defp unmerge_fragments([{:raw, s}], frag, args, _names, _part) do
    Enum.join [inspect(frag <> s)|Enum.reverse(args)], ", "
  end

  defp join_qual(:inner),         do: :join
  defp join_qual(:inner_lateral), do: :join_lateral
  defp join_qual(:left),          do: :left_join
  defp join_qual(:left_lateral),  do: :left_join_lateral
  defp join_qual(:right),         do: :right_join
  defp join_qual(:full),          do: :full_join
  defp join_qual(:cross),         do: :cross_join

  defp collect_sources(query) do
    [from_sources(query.from) | join_sources(query.joins)]
  end

  defp from_sources(%Ecto.SubQuery{query: query}), do: from_sources(query.from)
  defp from_sources({source, schema}), do: schema || source
  defp from_sources(nil), do: "query"

  defp join_sources(joins) do
    Enum.map(joins, fn
      %JoinExpr{assoc: {_var, assoc}} ->
        assoc
      %JoinExpr{source: {:fragment, _, _}} ->
        "fragment"
      %JoinExpr{source: %Ecto.Query{from: from}} ->
        from_sources(from)
      %JoinExpr{source: source} ->
        from_sources(source)
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
