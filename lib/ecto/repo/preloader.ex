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
        {:assoc, assoc, HashDict.new}
      ids ->
        query =
          if query do
            assoc.__struct__.assoc_query(assoc, query, ids)
          else
            assoc.__struct__.assoc_query(assoc, ids)
          end
        preload_assoc(repo, query, prefix, assoc, related_key, preloads)
    end
  end

  defp preload_assoc(repo, query, prefix, %{cardinality: card} = assoc, related_key, preloads) do
    if card == :many do
      # Generate the expression by hand so we prepend it instead of appending it
      query = update_in query.order_bys, fn order_bys ->
        [%Ecto.Query.QueryExpr{expr: [asc: {{:., [], [{:&, [], [0]}, related_key]}, [], []}],
                               file: __ENV__.file, line: __ENV__.line, params: []}|order_bys]
      end
    end
    loaded = preload_each(repo.all(%{query | prefix: prefix}), repo, preloads)
    {:assoc, assoc, assoc_dict(card, related_key, loaded)}
  end

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

  defp assoc_dict(:one, key, structs) do
    Enum.reduce structs, HashDict.new, fn x, acc ->
      HashDict.put(acc, Map.fetch!(x, key), x)
    end
  end

  defp assoc_dict(:many, key, structs) do
    many_assoc_dict(structs, key, HashDict.new)
  end

  defp many_assoc_dict([], _key, dict) do
    dict
  end

  defp many_assoc_dict([h|t], key, dict) do
    current  = Map.fetch!(h, key)
    {t1, t2} = Enum.split_while(t, &(Map.fetch!(&1, key) == current))
    many_assoc_dict(t2, key, HashDict.put(dict, current, [h|t1]))
  end

  ## Load preloaded data

  defp load_assoc(struct, assoc, dict) do
    key = Map.fetch!(struct, assoc.owner_key)

    loaded =
      cond do
        value = HashDict.get(dict, key) -> value
        assoc.cardinality == :many -> []
        true -> nil
      end

    Map.put(struct, assoc.field, loaded)
  end

  defp load_through(struct, assoc, [h|t]) do
    initial = struct |> Map.fetch!(h) |> List.wrap
    loaded  = Enum.reduce(t, initial, &recur_through/2)

    if assoc.cardinality == :one do
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
          assoc = Ecto.Association.association_from_model!(model, preload)
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
