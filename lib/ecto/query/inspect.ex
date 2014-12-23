defimpl Inspect, for: Ecto.Query do
  import Inspect.Algebra

  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr

  def inspect(query, opts) do
    case to_list(query) do
      [_] ->
        "#Ecto.Query<#{unbound_from(query.from)}>"
      list ->
        list = Enum.map(list, fn
          {key, string} ->
            concat(Atom.to_string(key) <> ": ", string)
          string ->
            string
        end)

        surround_many("#Ecto.Query<", list, ">", opts, fn str, _ -> str end)
    end
  end

  def to_string(query) do
    case to_list(query) do
      [_] ->
        unbound_from(query.from)
      list ->
        Enum.map_join(list, ",\n  ", fn
          {key, string} ->
            Atom.to_string(key) <> ": " <> string
          string ->
            string
        end)
    end
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
    wheres    = Enum.map(query.wheres, &{:where, expr(&1, names)})
    group_bys = Enum.map(query.group_bys, &{:group_by, expr(&1, names)})
    havings   = Enum.map(query.havings, &{:having, expr(&1, names)})
    order_bys = Enum.map(query.order_bys, &{:order_by, expr(&1, names)})
    preloads  = Enum.map(query.preloads, &{:preload, inspect(&1)})
    limit     = kw_expr(:limit, query.limit, names)
    offset    = kw_expr(:offset, query.offset, names)
    select    = kw_expr(:select, query.select, names)
    lock      = kw_inspect(:lock, query.lock)

    Enum.concat [from, joins, wheres, group_bys, havings, order_bys, limit, offset, lock, select, preloads]
  end

  defp bound_from(from, name), do: ["from #{name} in #{unbound_from from}"]

  defp unbound_from({source, nil}),    do: inspect source
  defp unbound_from({_source, model}), do: inspect model
  defp unbound_from(nil),              do: "query"

  defp joins(joins, names) do
    Enum.reduce(joins, {1, []}, fn expr, {ix, acc} ->
      string = join(expr, elem(names, ix), names)
      {ix + 1, [string|acc]}
    end)
    |> elem(1)
    |> Enum.reverse
    |> Enum.concat
  end

  defp join(%JoinExpr{qual: qual, assoc: {ix, right}, on: on}, name, names) do
    string = "#{name} in #{elem(names, ix)}.#{right}"
    [{join_qual(qual), string}, on: expr(on, names)]
  end

  defp join(%JoinExpr{qual: qual, source: {source, model}, on: on}, name, names) do
    string = "#{name} in #{inspect model || source}"
    [{join_qual(qual), string}, on: expr(on, names)]
  end

  defp kw_expr(_key, nil, _names), do: []
  defp kw_expr(key, %QueryExpr{expr: expr, params: params}, names) do
    [{key, expr(expr, names, params)}]
  end

  defp kw_inspect(_key, nil), do: []
  defp kw_inspect(key, val),  do: [{key, inspect(val)}]

  defp expr(%QueryExpr{expr: expr, params: params}, names) do
    expr(expr, names, params)
  end

  defp expr(expr, names, params) do
    Macro.to_string(expr, &expr_to_string(&1, &2, names, params))
  end

  defp expr_to_string({:fragment, _, parts}, _, names, params) do
    "fragment(" <> unmerge_fragments(parts, "", [], names, params) <> ")"
  end

  # Convert variables to proper identifiers
  defp expr_to_string({:&, _, [ix]}, _, names, _) do
    elem(names, ix)
  end

  # Inject the interpolated value
  #
  # In case the query had its parameters removed,
  # we use ... to express the interpolated code.
  defp expr_to_string({:^, _, [ix]}, _, _, params) do
    escaped =
      case Map.get(params || %{}, ix) do
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
  defp expr_to_string(%Ecto.Query.Tagged{value: value, type: :binary}, _, _names, _params) do
    inspect value
  end

  defp expr_to_string(%Ecto.Query.Tagged{value: value, type: type}, _, names, params) do
    {type, [], [value]}
    |> expr(names, params)
  end

  defp expr_to_string(_expr, string, _, _) do
    string
  end

  defp unmerge_fragments([s, v|t], frag, args, names, params) do
    unmerge_fragments(t, frag <> s <> "?", [expr(v, names, params)|args], names, params)
  end

  defp unmerge_fragments([s], frag, args, _names, _params) do
    Enum.join [inspect(frag <> s)|Enum.reverse(args)], ", "
  end

  defp join_qual(:inner), do: :join
  defp join_qual(:left),  do: :left_join
  defp join_qual(:right), do: :right_join
  defp join_qual(:outer), do: :outer_join

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
