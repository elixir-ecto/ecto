import Inspect.Algebra
import Kernel, except: [to_string: 1]

alias Ecto.Query.{BooleanExpr, DynamicExpr, JoinExpr, QueryExpr, WithExpr}

defimpl Inspect, for: Ecto.Query.DynamicExpr do
  def inspect(%DynamicExpr{binding: binding} = dynamic, opts) do
    joins =
      binding
      |> Enum.drop(1)
      |> Enum.with_index()
      |> Enum.map(&%JoinExpr{ix: &1})

    aliases =
      for({as, _} when is_atom(as) <- binding, do: as)
      |> Enum.with_index()
      |> Map.new

    query = %Ecto.Query{joins: joins, aliases: aliases}

    {expr, binding, params, _, _} = Ecto.Query.Builder.Dynamic.fully_expand(query, dynamic)

    names = Enum.map(binding, fn
      {_, {name, _, _}} -> Atom.to_string(name)
      {name, _, _} -> Atom.to_string(name)
    end)

    inspected = Inspect.Ecto.Query.expr(expr, List.to_tuple(names), %{expr: expr, params: params})

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
          Enum.map(queries, fn {name, query} ->
            cte = case query do
              %Ecto.Query{} -> __MODULE__.inspect(query, opts)
              %Ecto.Query.QueryExpr{} -> expr(query, {})
            end

            concat(["|> with_cte(\"" <> name <> "\", as: ", cte, ")"])
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
      |> collect_sources
      |> generate_letters
      |> generate_names
      |> List.to_tuple()

    from = bound_from(query.from, binding(names, 0))
    joins = joins(query.joins, names)
    preloads = preloads(query.preloads)
    assocs = assocs(query.assocs, names)
    windows = windows(query.windows, names)
    combinations = combinations(query.combinations)

    wheres = bool_exprs(%{and: :where, or: :or_where}, query.wheres, names)
    group_bys = kw_exprs(:group_by, query.group_bys, names)
    havings = bool_exprs(%{and: :having, or: :or_having}, query.havings, names)
    order_bys = kw_exprs(:order_by, query.order_bys, names)
    updates = kw_exprs(:update, query.updates, names)

    lock = kw_inspect(:lock, query.lock)
    limit = kw_expr(:limit, query.limit, names)
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

  defp bound_from(nil, name), do: ["from #{name} in query"]

  defp bound_from(%{source: source} = from, name) do
    ["from #{name} in #{inspect_source(source)}"] ++ kw_as_and_prefix(from)
  end

  defp inspect_source(%Ecto.Query{} = query), do: "^" <> inspect(query)
  defp inspect_source(%Ecto.SubQuery{query: query}), do: "subquery(#{to_string(query)})"
  defp inspect_source({source, nil}), do: inspect(source)
  defp inspect_source({nil, schema}), do: inspect(schema)

  defp inspect_source({source, schema} = from) do
    inspect(if source == schema.__schema__(:source), do: schema, else: from)
  end

  defp joins(joins, names) do
    joins
    |> Enum.with_index()
    |> Enum.flat_map(fn {expr, ix} -> join(expr, binding(names, expr.ix || ix + 1), names) end)
  end

  defp join(%JoinExpr{qual: qual, assoc: {ix, right}, on: on} = join, name, names) do
    string = "#{name} in assoc(#{binding(names, ix)}, #{inspect(right)})"
    [{join_qual(qual), string}] ++ kw_as_and_prefix(join) ++ maybe_on(on, names)
  end

  defp join(
         %JoinExpr{qual: qual, source: {:fragment, _, _} = source, on: on} = join = part,
         name,
         names
       ) do
    string = "#{name} in #{expr(source, names, part)}"
    [{join_qual(qual), string}] ++ kw_as_and_prefix(join) ++ [on: expr(on, names)]
  end

  defp join(%JoinExpr{qual: qual, source: source, on: on} = join, name, names) do
    string = "#{name} in #{inspect_source(source)}"
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
    Macro.to_string(expr, &expr_to_string(&1, &2, names, part))
  end

  # For keyword and interpolated fragments use normal escaping
  defp expr_to_string({:fragment, _, [{_, _} | _] = parts}, _, names, part) do
    "fragment(" <> unmerge_fragments(parts, "", [], names, part) <> ")"
  end

  # Convert variables to proper names
  defp expr_to_string({:&, _, [ix]}, _, names, %{take: take}) do
    case take do
      %{^ix => {:any, fields}} when ix == 0 ->
        Kernel.inspect(fields)

      %{^ix => {tag, fields}} ->
        "#{tag}(" <> binding(names, ix) <> ", " <> Kernel.inspect(fields) <> ")"

      _ ->
        binding(names, ix)
    end
  end

  defp expr_to_string({:&, _, [ix]}, _, names, _) do
    binding(names, ix)
  end

  # Inject the interpolated value
  #
  # In case the query had its parameters removed,
  # we use ... to express the interpolated code.
  defp expr_to_string({:^, _, [_ix, _len]}, _, _, _part) do
    Macro.to_string({:^, [], [{:..., [], nil}]})
  end

  defp expr_to_string({:^, _, [ix]}, _, _, %{params: params}) do
    case Enum.at(params || [], ix) do
      {value, _type} -> "^" <> Kernel.inspect(value, charlists: :as_lists)
      _ -> "^..."
    end
  end

  # Strip trailing ()
  defp expr_to_string({{:., _, [_, _]}, _, []}, string, _, _) do
    size = byte_size(string)
    :binary.part(string, 0, size - 2)
  end

  # Types need to be converted back to AST for fields
  defp expr_to_string({:type, [], [expr, type]}, _string, names, part) do
    "type(#{expr(expr, names, part)}, #{type |> type_to_expr() |> expr(names, part)})"
  end

  # Tagged values
  defp expr_to_string(%Ecto.Query.Tagged{value: value, tag: nil}, _, _names, _) do
    inspect(value)
  end

  defp expr_to_string(%Ecto.Query.Tagged{value: value, tag: tag}, _, names, part) do
    {:type, [], [value, tag]} |> expr(names, part)
  end

  defp expr_to_string({:json_extract_path, _, [expr, path]}, _, names, part) do
    json_expr_path_to_expr(expr, path) |> expr(names, part)
  end

  defp expr_to_string({:{}, [], [:subquery, i]}, _string, _names, %BooleanExpr{subqueries: subqueries}) do
    # We were supposed to match on {:subquery, i} but Elixir incorrectly
    # translates those to `:{}` when converting to string.
    # See https://github.com/elixir-lang/elixir/blob/27bd9ffcc607b74ce56b547cb6ba92c9012c317c/lib/elixir/lib/macro.ex#L932
    inspect_source(Enum.fetch!(subqueries, i))
  end

  defp expr_to_string(_expr, string, _, _) do
    string
  end

  defp type_to_expr({composite, type}) when is_atom(composite) do
    {composite, type_to_expr(type)}
  end

  defp type_to_expr({part, type}) when is_integer(part) do
    {{:., [], [{:&, [], [part]}, type]}, [], []}
  end

  defp type_to_expr(type) do
    type
  end

  defp json_expr_path_to_expr(expr, path) do
    Enum.reduce(path, expr, fn element, acc ->
      {{:., [], [Access, :get]}, [], [acc, element]}
    end)
  end

  defp unmerge_fragments([{:raw, s}, {:expr, v} | t], frag, args, names, part) do
    unmerge_fragments(t, frag <> s <> "?", [expr(v, names, part) | args], names, part)
  end

  defp unmerge_fragments([{:raw, s}], frag, args, _names, _part) do
    Enum.join([inspect(frag <> s) | Enum.reverse(args)], ", ")
  end

  defp join_qual(:inner), do: :join
  defp join_qual(:inner_lateral), do: :join_lateral
  defp join_qual(:left), do: :left_join
  defp join_qual(:left_lateral), do: :left_join_lateral
  defp join_qual(:right), do: :right_join
  defp join_qual(:full), do: :full_join
  defp join_qual(:cross), do: :cross_join

  defp collect_sources(%{from: nil, joins: joins}) do
    ["query" | join_sources(joins)]
  end

  defp collect_sources(%{from: %{source: source}, joins: joins}) do
    [from_sources(source) | join_sources(joins)]
  end

  defp from_sources(%Ecto.SubQuery{query: query}), do: from_sources(query.from.source)
  defp from_sources({source, schema}), do: schema || source
  defp from_sources(nil), do: "query"

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
    {names, _} = Enum.map_reduce(letters, 0, &{"#{&1}#{&2}", &2 + 1})
    names
  end

  defp binding(names, pos) do
    try do
      elem(names, pos)
    rescue
      ArgumentError -> "unknown_binding_#{pos}!"
    end
  end

  defp normalize_source("Elixir." <> _ = source),
    do: source |> Module.split() |> List.last()

  defp normalize_source(source),
    do: source
end
