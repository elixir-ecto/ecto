defimpl Inspect, for: Ecto.Query do
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr
  alias Ecto.Query.Util
  import Inspect.Algebra

  def inspect(query, opts) do
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
    limit     = limit(query.limit, names)
    offset    = offset(query.offset, names)
    lock      = lock(query.lock)
    select    = select(query.select, names)

    list = [from, joins, wheres, group_bys, havings, order_bys, limit, offset, lock, select]
           |> Enum.concat

    case list do
      [_] ->
        "#Ecto.Query<#{unbound_from(query.from)}>"
      _ ->
        surround_many("#Ecto.Query<", query(list), ">", opts, fn str, _ -> str end)
    end
  end

  defp unbound_from({source, nil}),    do: inspect source
  defp unbound_from({_source, model}), do: inspect model

  defp bound_from({source, nil}, name),    do: ["from #{name} in #{inspect source}"]
  defp bound_from({_source, model}, name), do: ["from #{name} in #{inspect model}"]

  defp joins(joins, names) do
    Enum.reduce(joins, {1, []}, fn expr, {ix, acc} ->
      string = join(expr, elem(names, ix), names)
      {ix + 1, [string|acc]}
    end)
    |> elem(1)
    |> Enum.reverse
    |> Enum.concat
  end

  defp join(%JoinExpr{qual: qual, assoc: {{:&, _, [ix]}, right}}, name, names) do
    string = "#{name} in #{elem(names, ix)}.#{right}"
    [{join_qual(qual), string}]
  end

  defp join(%JoinExpr{qual: qual, source: source, on: on}, name, names) do
    string = "#{name} in #{inspect source}"
    [{join_qual(qual), string}, on: expr(on, names)]
  end

  defp limit(nil, _names), do: []
  defp limit(expr, names), do: [limit: expr(expr, names)]

  defp offset(nil, _names), do: []
  defp offset(expr, names), do: [offset: expr(expr, names)]

  defp lock(nil),   do: []
  defp lock(false), do: [lock: "false"]
  defp lock(true),  do: [lock: "true"]
  defp lock(str),   do: [lock: inspect str]

  defp select(nil, _names), do: []
  defp select(expr, names), do: [select: expr(expr, names)]

  defp expr(%QueryExpr{expr: expr, external: external}, names) do
    expr(expr, names, external)
  end

  defp expr(expr, names, external) do
    Macro.to_string(expr, &expr_to_string(&1, &2, names, external))
  end

  # Convert variables to proper identifiers
  defp expr_to_string({:&, _, [ix]}, _, names, _) do
    elem(names, ix)
  end

  # Inject the interpolated value
  defp expr_to_string({:^, _, [ix]}, _, _, external) do
    escaped = Map.get(external, ix) |> Macro.escape
    expr = {:^, [], [escaped]}
    Macro.to_string(expr)
  end

  # Strip trailing ()
  defp expr_to_string({{:., _, [_, _]}, _, []}, string, _, _) do
    size = byte_size(string)
    :binary.part(string, 0, size - 2)
  end

  # Tagged values
  defp expr_to_string(%Ecto.Tagged{value: value, type: {outer, inner}}, _, names, external) do
    {outer, [], [value, inner]}
    |> expr(names, external)
  end

  defp expr_to_string(%Ecto.Tagged{value: value, type: type}, _, names, external) do
    {type, [], [value]}
    |> expr(names, external)
  end

  defp expr_to_string(_expr, string, _, _) do
    string
  end

  defp join_qual(:inner), do: :join
  defp join_qual(:left),  do: :left_join
  defp join_qual(:right), do: :right_join
  defp join_qual(:outer), do: :outer_join

  defp query(kw) do
    Enum.map(kw, fn
      {key, string} ->
        concat(Atom.to_string(key) <> ": ", string)
      string ->
        string
    end)
  end

  defp collect_sources(query) do
    case query.from do
      {source, nil} ->
        sources = [source]
      {_source, model} ->
        sources = [model]
    end

    Enum.reduce(query.joins, sources, fn
      %JoinExpr{assoc: {left, right}}, acc ->
        model = Util.find_source(Enum.reverse(acc), left)

        if model && (refl = model.__schema__(:association, right)) do
          assoc = refl.associated
          [assoc|acc]
        else
          [right|acc]
        end

      %JoinExpr{source: source}, acc ->
        [source|acc]
    end)
    |> Enum.reverse
  end

  defp generate_letters(sources) do
    Enum.map(sources, fn source ->
      source
      |> to_string
      |> normalize_source
      |> binary_first
      |> String.downcase
    end)
  end

  defp generate_names(letters) do
    generate_names(letters, [])
  end

  defp generate_names([letter|rest], acc) do
    cond do
      name = Enum.find(acc, &(binary_first(&1) == letter)) ->
        index = name |> binary_rest |> String.to_integer
        new_name = "#{letter}#{index + 1}"
        generate_names(rest, [new_name|acc])
      Enum.any?(rest, &(&1 == letter)) ->
        new_name = "#{letter}0"
        generate_names(rest, [new_name|acc])
      true ->
        generate_names(rest, [letter|acc])
    end
  end

  defp generate_names([], acc) do
    Enum.reverse(acc)
  end

  defp normalize_source("Elixir." <> _ = source),
    do: source |> Module.split |> List.last
  defp normalize_source(source),
    do: source

  defp binary_first(<<letter, _ :: binary>>), do: <<letter>>

  defp binary_rest(<<_, rest :: binary>>), do: rest
end
