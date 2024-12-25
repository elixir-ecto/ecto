import Inspect.Algebra
import Kernel, except: [to_string: 1]

alias Ecto.Query.{DynamicExpr, JoinExpr, QueryExpr, WithExpr, LimitExpr}

defimpl Inspect, for: Ecto.Query.DynamicExpr do
  def inspect(%DynamicExpr{binding: binding} = dynamic, opts) do
    binding =
      Enum.map(binding, fn
        {{:^, _, [as]}, bind} when is_atom(as) -> {as, bind}
        other -> other
      end)

    dynamic = %{dynamic | binding: binding}

    joins =
      binding
      |> Enum.drop(1)
      |> Enum.with_index()
      |> Enum.map(&%JoinExpr{ix: &1})

    aliases =
      for({as, _} when is_atom(as) <- binding, do: as)
      |> Enum.with_index()
      |> Map.new()

    query = %Ecto.Query{joins: joins, aliases: aliases}

    {expr, binding, params, subqueries, _, _} =
      Ecto.Query.Builder.Dynamic.fully_expand(query, dynamic)

    names =
      Enum.map(binding, fn
        {_, {name, _, _}} -> name
        {name, _, _} -> name
      end)

    query_expr = %{expr: expr, params: params, subqueries: subqueries}
    inspected = Inspect.Ecto.Query.expr(expr, List.to_tuple(names), query_expr)

    container_doc("dynamic(", [Macro.to_string(binding), inspected], ")", opts, fn str, _ ->
      str
    end)
  end
end

defimpl Inspect, for: Ecto.Query do
  @doc false
  def inspect(query, opts) do
    list =
      Enum.map(to_list(query), fn
        {key, string} ->
          concat(Atom.to_string(key) <> ": ", string)

        string ->
          string
      end)

    result = container_doc("#Ecto.Query<", list, ">", opts, fn str, _ -> str end)

    case query.with_ctes do
      %WithExpr{recursive: recursive, queries: [_ | _] = queries} ->
        with_ctes =
          Enum.map(queries, fn {name, cte_opts, query} ->
            cte =
              case query do
                %Ecto.Query{} -> __MODULE__.inspect(query, opts)
                %Ecto.Query.QueryExpr{} -> expr(query, {})
              end

            concat([
              "|> with_cte(\"" <> name <> "\", materialized: ",
              inspect(cte_opts[:materialized]),
              ", as: ",
              cte,
              ")"
            ])
          end)

        result = if recursive, do: glue(result, "\n", "|> recursive_ctes(true)"), else: result
        [result | with_ctes] |> Enum.intersperse(break("\n")) |> concat()

      _ ->
        result
    end
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
      |> collect_sources()
      |> generate_letters()
      |> generate_names()
      |> List.to_tuple()

    from = bound_from(query.from, elem(names, 0), names)
    joins = joins(query.joins, names)
    preloads = preloads(query.preloads)
    assocs = assocs(query.assocs, names)
    windows = windows(query.windows, names)
    combinations = combinations(query.combinations)
    limit = limit(query.limit, names)

    wheres = bool_exprs(%{and: :where, or: :or_where}, query.wheres, names)
    group_bys = kw_exprs(:group_by, query.group_bys, names)
    havings = bool_exprs(%{and: :having, or: :or_having}, query.havings, names)
    order_bys = kw_exprs(:order_by, query.order_bys, names)
    updates = kw_exprs(:update, query.updates, names)

    lock = kw_inspect(:lock, query.lock)
    offset = kw_expr(:offset, query.offset, names)
    select = kw_expr(:select, query.select, names)
    distinct = kw_expr(:distinct, query.distinct, names)

    Enum.concat([
      from,
      joins,
      wheres,
      group_bys,
      havings,
      windows,
      combinations,
      order_bys,
      limit,
      offset,
      lock,
      distinct,
      updates,
      select,
      preloads,
      assocs
    ])
  end

  defp bound_from(nil, name, _names), do: ["from #{name} in query"]

  defp bound_from(from, name, names) do
    ["from #{name} in #{inspect_source(from, names)}"] ++ kw_as_and_prefix(from)
  end

  defp inspect_source(%{source: %Ecto.Query{} = query}, _names), do: "^" <> inspect(query)

  defp inspect_source(%{source: %Ecto.SubQuery{query: query}}, _names),
    do: "subquery(#{to_string(query)})"

  defp inspect_source(%{source: {source, nil}}, _names), do: inspect(source)
  defp inspect_source(%{source: {nil, schema}}, _names), do: inspect(schema)

  defp inspect_source(%{source: {:fragment, _, _} = source} = part, names),
    do: "#{expr(source, names, part)}"

  defp inspect_source(%{source: {:values, _, [types | _]}}, _names) do
    fields = Keyword.keys(types)
    "values (#{Enum.join(fields, ", ")})"
  end

  defp inspect_source(%{source: {source, schema}}, _names) do
    inspect(if source == schema.__schema__(:source), do: schema, else: {source, schema})
  end

  defp joins(joins, names) do
    joins
    |> Enum.with_index()
    |> Enum.flat_map(fn {expr, ix} -> join(expr, elem(names, expr.ix || ix + 1), names) end)
  end

  defp join(%JoinExpr{qual: qual, assoc: {ix, right}, on: on} = join, name, names) do
    string = "#{name} in assoc(#{elem(names, ix)}, #{inspect(right)})"
    [{join_qual(qual), string}] ++ kw_as_and_prefix(join) ++ maybe_on(on, names)
  end

  defp join(%JoinExpr{qual: qual, on: on} = join, name, names) do
    string = "#{name} in #{inspect_source(join, names)}"
    [{join_qual(qual), string}] ++ kw_as_and_prefix(join) ++ [on: expr(on, names)]
  end

  defp maybe_on(%QueryExpr{expr: true}, _names), do: []
  defp maybe_on(%QueryExpr{} = on, names), do: [on: expr(on, names)]

  defp preloads([]), do: []
  defp preloads(preloads), do: [preload: inspect(preloads)]

  defp assocs([], _names), do: []
  defp assocs(assocs, names), do: [preload: expr(assocs(assocs), names, %{})]

  defp assocs(assocs) do
    Enum.map(assocs, fn
      {field, {idx, []}} ->
        {field, {:&, [], [idx]}}

      {field, {idx, children}} ->
        {field, {{:&, [], [idx]}, assocs(children)}}
    end)
  end

  defp windows(windows, names) do
    Enum.map(windows, &window(&1, names))
  end

  defp window({name, %{expr: definition} = part}, names) do
    {:windows, "[#{name}: " <> expr(definition, names, part) <> "]"}
  end

  defp combinations(combinations) do
    Enum.map(combinations, fn {key, val} -> {key, "(" <> to_string(val) <> ")"} end)
  end

  defp limit(nil, _names), do: []

  defp limit(%LimitExpr{with_ties: false} = limit, names) do
    [{:limit, expr(limit, names)}]
  end

  defp limit(%LimitExpr{with_ties: with_ties} = limit, names) do
    [{:limit, expr(limit, names)}] ++ kw_inspect(:with_ties, with_ties)
  end

  defp bool_exprs(keys, exprs, names) do
    Enum.map(exprs, fn %{expr: expr, op: op} = part ->
      {Map.fetch!(keys, op), expr(expr, names, part)}
    end)
  end

  defp kw_exprs(key, exprs, names) do
    Enum.map(exprs, &{key, expr(&1, names)})
  end

  defp kw_expr(_key, nil, _names), do: []
  defp kw_expr(key, expr, names), do: [{key, expr(expr, names)}]

  defp kw_inspect(_key, nil), do: []
  defp kw_inspect(key, val), do: [{key, inspect(val)}]

  defp kw_as_and_prefix(%{as: as, prefix: prefix}) do
    kw_inspect(:as, as) ++ kw_inspect(:prefix, prefix)
  end

  defp expr(%{expr: expr} = part, names) do
    expr(expr, names, part)
  end

  @doc false
  def expr(expr, names, part) do
    expr
    |> Macro.traverse(:ok, &{prewalk(&1, names), &2}, &{postwalk(&1, names, part), &2})
    |> elem(0)
    |> macro_to_string()
  end

  defp macro_to_string(expr), do: Macro.to_string(expr)

  # Tagged values
  defp prewalk(%Ecto.Query.Tagged{value: value, tag: nil}, _) do
    value
  end

  defp prewalk(%Ecto.Query.Tagged{value: value, tag: tag}, _) do
    {:type, [], [value, tag]}
  end

  defp prewalk({{:., dot_meta, [{:&, _, [ix]}, field]}, meta, []}, names) do
    {{:., dot_meta, [binding(names, ix), field]}, meta, []}
  end

  defp prewalk(node, _) do
    node
  end

  # Convert variables to proper names
  defp postwalk({:&, _, [ix]}, names, part) do
    binding_to_expr(ix, names, part)
  end

  # Format field/2 with string name
  defp postwalk({{:., _, [{_, _, _} = binding, field]}, meta, []}, _names, _part)
       when is_binary(field) do
    {:field, meta, [binding, field]}
  end

  # Remove parens from field calls
  defp postwalk({{:., _, [_, _]} = dot, meta, []}, _names, _part) do
    {dot, [no_parens: true] ++ meta, []}
  end

  # Interpolated unknown value
  defp postwalk({:^, _, [_ix, _len]}, _names, _part) do
    {:^, [], [{:..., [], nil}]}
  end

  # Interpolated known value
  defp postwalk({:^, _, [ix]}, _, %{params: params}) do
    value =
      case Enum.at(params || [], ix) do
        # Wrap the head in a block so it is not treated as a charlist
        {[head | tail], _type} -> [{:__block__, [], [head]} | tail]
        {value, _type} -> value
        _ -> {:..., [], nil}
      end

    {:^, [], [value]}
  end

  # Types need to be converted back to AST for fields
  defp postwalk({:type, meta, [expr, type]}, names, part) do
    {:type, meta, [expr, type_to_expr(type, names, part)]}
  end

  # For keyword and interpolated fragments use normal escaping
  defp postwalk({:fragment, _, [{_, _} | _] = parts}, _names, _part) do
    {:fragment, [], unmerge_fragments(parts, "", [])}
  end

  # Subqueries
  defp postwalk({:subquery, i}, _names, %{subqueries: subqueries}) do
    {:subquery, [], [Enum.fetch!(subqueries, i).query]}
  end

  # Jason
  defp postwalk({:json_extract_path, _, [expr, path]}, _names, _part) do
    Enum.reduce(path, expr, fn element, acc ->
      {{:., [], [Access, :get]}, [], [acc, element]}
    end)
  end

  defp postwalk(node, _names, _part) do
    node
  end

  defp binding_to_expr(ix, names, part) do
    case part do
      %{take: %{^ix => {:any, fields}}} when ix == 0 ->
        fields

      %{take: %{^ix => {tag, fields}}} ->
        {tag, [], [binding(names, ix), fields]}

      _ ->
        binding(names, ix)
    end
  end

  defp type_to_expr({ix, type}, names, part) when is_integer(ix) do
    {{:., [], [binding_to_expr(ix, names, part), type]}, [no_parens: true], []}
  end

  defp type_to_expr({composite, type}, names, part) when is_atom(composite) do
    {composite, type_to_expr(type, names, part)}
  end

  defp type_to_expr(type, _names, _part) do
    type
  end

  defp unmerge_fragments([{:raw, s}, {:expr, v} | t], frag, args) do
    unmerge_fragments(t, frag <> s <> "?", [v | args])
  end

  defp unmerge_fragments([{:raw, s}], frag, args) do
    [frag <> s | Enum.reverse(args)]
  end

  defp join_qual(:inner), do: :join
  defp join_qual(:inner_lateral), do: :inner_lateral_join
  defp join_qual(:left), do: :left_join
  defp join_qual(:left_lateral), do: :left_lateral_join
  defp join_qual(:right), do: :right_join
  defp join_qual(:full), do: :full_join
  defp join_qual(:cross), do: :cross_join
  defp join_qual(:cross_lateral), do: :cross_lateral_join

  defp collect_sources(%{from: nil, joins: joins}) do
    ["query" | join_sources(joins)]
  end

  defp collect_sources(%{from: %{source: source}, joins: joins}) do
    [from_sources(source) | join_sources(joins)]
  end

  defp from_sources(%Ecto.SubQuery{query: query}), do: from_sources(query.from.source)
  defp from_sources({source, schema}), do: schema || source
  defp from_sources(nil), do: "query"
  defp from_sources({:fragment, _, _}), do: "fragment"
  defp from_sources({:values, _, _}), do: "values"

  defp join_sources(joins) do
    joins
    |> Enum.sort_by(& &1.ix)
    |> Enum.map(fn
      %JoinExpr{assoc: {_var, assoc}} ->
        assoc

      %JoinExpr{source: {:fragment, _, _}} ->
        "fragment"

      %JoinExpr{source: %Ecto.Query{from: from}} ->
        from_sources(from.source)

      %JoinExpr{source: source} ->
        from_sources(source)
    end)
  end

  defp generate_letters(sources) do
    Enum.map(sources, fn source ->
      source
      |> Kernel.to_string()
      |> normalize_source()
      |> String.first()
      |> String.downcase()
    end)
  end

  defp generate_names(letters) do
    {names, _} = Enum.map_reduce(letters, 0, &{:"#{&1}#{&2}", &2 + 1})
    names
  end

  defp binding(names, pos) do
    try do
      {elem(names, pos), [], nil}
    rescue
      ArgumentError -> {:"unknown_binding_#{pos}!", [], nil}
    end
  end

  defp normalize_source("Elixir." <> _ = source),
    do: source |> Module.split() |> List.last()

  defp normalize_source(source),
    do: source
end
