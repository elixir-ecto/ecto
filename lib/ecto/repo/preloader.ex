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
    preloads = normalize(preloads, assocs, preloads)
    do_preload(structs, repo, preloads)
  end

  defp do_preload(structs, _repo, []),   do: structs
  defp do_preload([], _repo, _preloads), do: []

  defp do_preload(structs, repo, preloads) do
    module = hd(structs).__struct__

    # TODO: What if structs are not the same
    # TODO: What if reflections is nil?

    entries =
      for {preload, sub_preloads} <- preloads do
        refl = module.__schema__(:association, preload)

        owner_key = refl.owner_key
        assoc_key = refl.assoc_key

        ids =
          for struct <- structs,
              key = Map.fetch!(struct, owner_key),
              do: key

        preloaded =
          if ids != [] do
            query = Ecto.Query.from x in refl.assoc,
                                  where: field(x, ^assoc_key) in ^ids,
                                  order_by: field(x, ^assoc_key)
            do_preload(repo.all(query), repo, sub_preloads)
          else
            []
          end

        {refl, into_dict(preloaded, refl.assoc_key, HashDict.new)}
      end

    for struct <- structs do
      Enum.reduce entries, struct, fn {refl, dict}, acc ->
        key    = Map.fetch!(acc, refl.owner_key)
        loaded = HashDict.get(dict, key, [])

        if refl.cardinality == :one do
          loaded = List.first(loaded)
        end

        Map.put(acc, refl.field, loaded)
      end
    end
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

  defp normalize(preload, assocs, original) do
    Enum.flat_map(List.wrap(preload), &normalize_each(&1, assocs, original))
  end

  defp normalize_each({atom, list}, assocs, original) when is_atom(atom) do
    no_assoc!(assocs, atom)
    [{atom, normalize(list, assocs, original)}]
  end

  defp normalize_each(atom, assocs, _original) when is_atom(atom) do
    no_assoc!(assocs, atom)
    [{atom, []}]
  end

  defp normalize_each(list, assocs, original) when is_list(list) do
    Enum.flat_map(list, &normalize_each(&1, assocs, original))
  end

  defp normalize_each(other, _assocs, original) do
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
end
