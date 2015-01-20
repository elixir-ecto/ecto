defmodule Ecto.Repo.Preloader do
  # The module invoked by user defined repos
  # for preload related functionality.
  @moduledoc false

  require Ecto.Query

  @doc """
  Transforms a result set based on query preloads, loading
  the associations onto their parent model.
  """
  @spec query([list], Ecto.Repo.t, Ecto.Query.t, fun) :: [list]
  def query([], _repo, _query, _fun),           do: []
  def query(rows, _repo, %{preloads: []}, fun), do: Enum.map(rows, fun)

  def query(rows, repo, query, fun) do
    rows
    |> extract
    |> do_preload(repo, query.preloads, query.assocs)
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
  @spec preload(models, atom, atom | list) :: models when models: [Ecto.Model.t] | Ecto.Model.t
  def preload(structs, repo, preloads) when is_list(structs) do
    do_preload(structs, repo, preloads, nil)
  end

  def preload(struct, repo, preloads) when is_map(struct) do
    do_preload([struct], repo, preloads, nil) |> hd()
  end

  ## Implementation

  defp do_preload(structs, repo, preloads, assocs) do
    preloads = normalize(preloads, [], assocs, preloads)
    do_preload(structs, repo, preloads)
  end

  defp do_preload(structs, _repo, []),   do: structs
  defp do_preload([], _repo, _preloads), do: []

  defp do_preload(structs, repo, preloads) do
    entries =
      for {preload, sub_preloads} <- preloads do
        assoc = Ecto.Associations.association_from_model!(hd(structs).__struct__, preload)
        query = Ecto.Model.assoc(structs, preload)

        if assoc.cardinality == :many do
          query = Ecto.Query.from q in query, order_by: field(q, ^assoc.assoc_key)
        end

        loaded = do_preload(repo.all(query), repo, sub_preloads)
        {assoc, into_dict(assoc, loaded)}
      end

    for struct <- structs do
      Enum.reduce entries, struct, fn {assoc, dict}, acc ->
        default = if assoc.cardinality == :one, do: nil, else: []
        key     = Map.fetch!(acc, assoc.owner_key)
        loaded  = HashDict.get(dict, key, default)
        Map.put(acc, assoc.field, loaded)
      end
    end
  end

  ## Loads and merges preloaded data

  defp into_dict(%{cardinality: :one, assoc_key: key}, structs) do
    Enum.reduce structs, HashDict.new, fn x, acc ->
      HashDict.put(acc, Map.fetch!(x, key), x)
    end
  end

  defp into_dict(%{assoc_key: key}, structs) do
    into_dict(structs, key, HashDict.new)
  end

  defp into_dict([], _key, dict) do
    dict
  end

  defp into_dict([h|t], key, dict) do
    current  = Map.fetch!(h, key)
    {t1, t2} = Enum.split_while(t, &(Map.fetch!(&1, key) == current))
    into_dict(t2, key, HashDict.put(dict, current, [h|t1]))
  end

  ## Normalizer

  defp normalize(preloads, acc, assocs, original) do
    Enum.reduce(List.wrap(preloads), acc, &normalize_each(&1, &2, assocs, original))
  end

  defp normalize_each({key, value}, acc, assocs, original) when is_atom(key) do
    no_assoc!(assocs, key)
    value = normalize(value, Keyword.get(acc, key, []), nil, original)
    Keyword.put(acc, key, value)
  end

  defp normalize_each(key, acc, assocs, _original) when is_atom(key) do
    no_assoc!(assocs, key)
    Keyword.put_new(acc, key, [])
  end

  defp normalize_each(list, acc, assocs, original) when is_list(list) do
    Enum.reduce(list, acc, &normalize_each(&1, &2, assocs, original))
  end

  defp normalize_each(other, _acc, _assocs, original) do
    raise ArgumentError, "invalid preload `#{inspect other}` in `#{inspect original}`. " <>
                         "preload expects an atom, a (nested) keyword or a (nested) list of atoms"
  end

  defp no_assoc!(nil, _atom), do: nil
  defp no_assoc!(assocs, atom) do
    if Keyword.has_key?(assocs, atom) do
      raise ArgumentError, "cannot preload association `#{inspect atom}` because " <>
                           "it has already been loaded with join association"
    end
  end
end
