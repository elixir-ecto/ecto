defmodule Ecto.Repo.Preloader do
  # The module invoked by user defined repos
  # for preload related functionality.
  @moduledoc false

  require Ecto.Query

  @doc """
  Transforms a result set based on query preloads, loading
  the associations onto their parent model.
  """
  @spec query([list], Ecto.Repo.t, list, list, fun) :: [list]
  def query([], _repo, _preloads, _assocs, _fun), do: []
  def query(rows, _repo, [], _assocs, fun), do: Enum.map(rows, fun)

  def query(rows, repo, preloads, assocs, fun) do
    rows
    |> extract
    |> do_preload(repo, preloads, assocs)
    |> unextract(rows, fun)
  end

  defp extract([[nil|_]|t2]), do: extract(t2)
  defp extract([[h|_]|t2]),   do: [h|extract(t2)]
  defp extract([]),           do: []

  defp unextract(structs, [[nil|_]=h2|t2], fun),  do: [fun.(h2)|unextract(structs, t2, fun)]
  defp unextract([h1|structs], [[_|t1]|t2], fun), do: [fun.([h1|t1])|unextract(structs, t2, fun)]
  defp unextract([], [], _fun),                   do: []

  @doc """
  Implementation for `Ecto.Repo.preload/2`.
  """
  @spec preload(models, atom, atom | list) :: models when models: [Ecto.Schema.t] | Ecto.Schema.t
  def preload(structs, repo, preloads) when is_list(structs) do
    do_preload(structs, repo, preloads, nil)
  end

  def preload(struct, repo, preloads) when is_map(struct) do
    do_preload([struct], repo, preloads, nil) |> hd()
  end

  defp do_preload(structs, repo, preloads, assocs) do
    preloads = normalize(preloads, assocs, preloads)
    preload_each(structs, repo, preloads)
  rescue
    e ->
      # Reraise errors so we ignore the preload inner stacktrace
      reraise e
  end

  ## Preloading

  defp preload_each(structs, _repo, []),   do: structs
  defp preload_each([], _repo, _preloads), do: []
  defp preload_each([sample|_] = structs, repo, preloads) do
    module      = sample.__struct__
    {prefix, _} = sample.__meta__.source
    preloads    = expand(module, preloads, [])

    entries =
      Enum.map preloads, fn
        {_, {:assoc, assoc, related_key}, sub_preloads} ->
          preload_assoc(structs, module, repo, prefix, assoc, related_key, sub_preloads)
        {_, {:through, _, _} = info, {nil, []}} ->
          info
      end

    for struct <- structs do
      Enum.reduce entries, struct, fn {kind, assoc, data}, acc ->
        cond do
          loaded?(acc, assoc.field) ->
            acc
          kind == :assoc ->
            load_assoc(acc, assoc, data)
          kind == :through ->
            load_through(acc, assoc, data)
        end
      end
    end
  end

  ## Association preloading

  defp preload_assoc(structs, module, repo, prefix, assoc, related_key, {query, preloads}) do
    case unique_ids(structs, module, assoc) do
      [] ->
        {:assoc, assoc, %{}}
      ids ->
        query = assoc.__struct__.assoc_query(assoc, query, ids)
        preload_assoc(repo, query, prefix, assoc, related_key, preloads)
    end
  end

  defp preload_assoc(repo, query, prefix, %{cardinality: card} = assoc, related_key, preloads) do
    field = related_key_to_field(query, related_key)

    # Normalize query
    query = ensure_select(query)

    # Add the related key to the query results
    query = update_in query.select.expr, &{:{}, [], [field, &1]}

    # If we are returning many results, we must sort by the key too
    if card == :many do
      query = update_in query.order_bys, fn order_bys ->
        [%Ecto.Query.QueryExpr{expr: [asc: field], params: [],
                               file: __ENV__.file, line: __ENV__.line}|order_bys]
      end
    end

    {ids, structs} = unzip repo.all(%{query | prefix: prefix}), [], []
    loaded = preload_each(structs, repo, preloads)
    {:assoc, assoc, assoc_map(card, ids, loaded)}
  end

  defp ensure_select(%{select: nil} = query) do
    select = %Ecto.Query.SelectExpr{expr: {:&, [], [0]}, line: __ENV__.line, file: __ENV__.file}
    %{query | select: select}
  end
  defp ensure_select(query) do
    query
  end

  defp related_key_to_field(query, {pos, key}) do
    {{:., [], [{:&, [], [related_key_pos(query, pos)]}, key]}, [], []}
  end

  defp related_key_pos(_query, pos) when pos >= 0, do: pos
  defp related_key_pos(query, pos), do: Ecto.Query.Builder.count_binds(query) + pos

  defp unzip([{k, v}|t], acc1, acc2), do: unzip(t, [k|acc1], [v|acc2])
  defp unzip([], acc1, acc2), do: {acc1, acc2}

  defp unique_ids(structs, module, assoc) do
    field = assoc.field
    owner_key = assoc.owner_key

    Enum.uniq for(struct <- structs,
      assert_struct!(module, struct),
      not loaded?(struct, field),
      key = Map.fetch!(struct, owner_key),
      do: key)
  end

  defp loaded?(struct, field) do
    case Map.get(struct, field) do
      %Ecto.Association.NotLoaded{} -> false
      _ -> true
    end
  end

  defp assert_struct!(model, %{__struct__: struct}) do
    if struct != model do
      raise ArgumentError, "expected a homogeneous list containing the same struct, " <>
                           "got: #{inspect model} and #{inspect struct}"
    else
      true
    end
  end

  defp assoc_map(:one, ids, structs) do
    one_assoc_map(ids, structs, %{})
  end
  defp assoc_map(:many, ids, structs) do
    many_assoc_map(ids, structs, %{})
  end

  defp one_assoc_map([id|ids], [struct|structs], map) do
    one_assoc_map(ids, structs, Map.put(map, id, struct))
  end
  defp one_assoc_map([], [], map) do
    map
  end

  defp many_assoc_map([id|ids], [struct|structs], map) do
    {ids, structs, acc} = split_while(ids, structs, id, [struct])
    many_assoc_map(ids, structs, Map.put(map, id, acc))
  end
  defp many_assoc_map([], [], map) do
    map
  end

  defp split_while([id|ids], [struct|structs], id, acc),
    do: split_while(ids, structs, id, [struct|acc])
  defp split_while(ids, structs, _id, acc),
    do: {ids, structs, acc}

  ## Load preloaded data

  defp load_assoc(struct, assoc, map) do
    %{field: field, owner_key: owner_key, cardinality: cardinality} = assoc
    key = Map.fetch!(struct, owner_key)

    loaded =
      case map do
        %{^key => value} -> value
        _ when cardinality == :many -> []
        _ -> nil
      end

    Map.put(struct, field, loaded)
  end

  defp load_through(struct, %{cardinality: cardinality} = assoc, [h|t]) do
    initial = struct |> Map.fetch!(h) |> List.wrap
    loaded  = Enum.reduce(t, initial, &recur_through/2)

    if cardinality == :one do
      loaded = List.first(loaded)
    end

    Map.put(struct, assoc.field, loaded)
  end

  defp recur_through(assoc, structs) do
    Enum.reduce(structs, {[], HashSet.new}, fn struct, acc ->
      children = struct |> Map.fetch!(assoc) |> List.wrap

      Enum.reduce children, acc, fn child, {fresh, set} ->
        [{_, pk}] = Ecto.primary_key!(child)
        pk || raise Ecto.NoPrimaryKeyValueError, struct: child

        if HashSet.member?(set, pk) do
          {fresh, set}
        else
          {[child|fresh], HashSet.put(set, pk)}
        end
      end
    end) |> elem(0) |> Enum.reverse()
  end

  ## Normalizer

  def normalize(preload, assocs, original) do
    normalize_each(wrap(preload, original), [], assocs, original)
  end

  defp normalize_each({atom, {%Ecto.Query{} = query, list}}, acc, assocs, original) when is_atom(atom) do
    no_assoc!(assocs, atom)
    [{atom, {query, normalize_each(wrap(list, original), [], nil, original)}}|acc]
  end

  defp normalize_each({atom, %Ecto.Query{} = query}, acc, assocs, _original) when is_atom(atom) do
    no_assoc!(assocs, atom)
    [{atom, {query, []}}|acc]
  end

  defp normalize_each({atom, list}, acc, assocs, original) when is_atom(atom) do
    no_assoc!(assocs, atom)
    [{atom, {nil, normalize_each(wrap(list, original), [], nil, original)}}|acc]
  end

  defp normalize_each(atom, acc, assocs, _original) when is_atom(atom) do
    no_assoc!(assocs, atom)
    [{atom, {nil, []}}|acc]
  end

  defp normalize_each(other, acc, assocs, original) do
    Enum.reduce(wrap(other, original), acc, &normalize_each(&1, &2, assocs, original))
  end

  defp wrap(list, _original) when is_list(list),
    do: list
  defp wrap(atom, _original) when is_atom(atom),
    do: atom
  defp wrap(other, original) do
    raise ArgumentError, "invalid preload `#{inspect other}` in `#{inspect original}`. " <>
                         "preload expects an atom, a (nested) keyword or a (nested) list of atoms"
  end

  defp no_assoc!(nil, _atom), do: nil
  defp no_assoc!(assocs, atom) do
    if assocs[atom] do
      raise ArgumentError, "cannot preload association `#{inspect atom}` because " <>
                           "it has already been loaded with join association"
    end
  end

  ## Expand

  def expand(model, preloads, acc) do
    Enum.reduce(preloads, acc, fn {preload, sub_preloads}, acc ->
      case List.keyfind(acc, preload, 0) do
        {^preload, info, extra_preloads} ->
          List.keyreplace(acc, preload, 0,
                          {preload, info, merge_preloads(preload, sub_preloads, extra_preloads)})
        nil ->
          assoc = Ecto.Association.association_from_schema!(model, preload)
          info  = assoc.__struct__.preload_info(assoc)

          case info do
            {:assoc, _, _} ->
              [{preload, info, sub_preloads}|acc]
            {:through, _, through} ->
              through =
                through
                |> Enum.reverse
                |> Enum.reduce(sub_preloads, &{nil, [{&1, &2}]})
                |> elem(1)
              List.keystore(expand(model, through, acc), preload, 0, {preload, info, {nil, []}})
          end
      end
    end)
  end

  defp merge_preloads(_preload, {nil, left}, {query, right}),
    do: {query, left ++ right}
  defp merge_preloads(_preload, {query, left}, {nil, right}),
    do: {query, left ++ right}
  defp merge_preloads(preload, {left, _}, {right, _}) do
    raise ArgumentError, "cannot preload `#{preload}` as it has been supplied more than once " <>
                         "with different queries: #{inspect left} and #{inspect right}"
  end

  defp reraise(exception) do
    reraise exception, Enum.reject(System.stacktrace, &match?({__MODULE__, _, _, _}, &1))
  end
end
