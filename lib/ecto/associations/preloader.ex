defmodule Ecto.Associations.Preloader do
  @moduledoc """
  This module provides assoc selector merger.
  """

  alias Ecto.Associations.BelongsTo
  require Ecto.Query, as: Q

  @doc """
  Transforms a result set based on query preloads, loading
  the associations onto their parent model.
  """
  @spec query([Ecto.Model.t], Ecto.Repo.t, Ecto.Query.t) :: [Ecto.Model.t]

  def query([], _repo, _query),            do: []
  def query(rows, _repo, %{preloads: []}), do: rows

  def query(rows, repo, query) do
    rows
    |> extract
    |> run(repo, query.preloads, query.assocs)
    |> unextract(rows)
  end

  @doc """
  Loads all associations on the result set.

  `fields` is a list of fields that can be nested in rose tree
  structure:

      node :: {atom, [node | atom]}

  See `Ecto.Query.preload/2`.
  """
  @spec run([Ecto.Model.t], atom, [atom | tuple]) :: [Ecto.Model.t]
  def run(structs, repo, fields) do
    run(structs, repo, fields, [])
  end

  defp run([], _repo, _fields, _assocs), do: []
  defp run(structs, _repo, [], _assocs), do: structs
  defp run(structs, repo, fields, assocs) do
    fields
    |> normalize(assocs, fields)
    |> Enum.reduce(structs, &do_run(&2, repo, &1))
  end

  # Receives a list of model struct to preload the given association fields
  # on. The fields given are a rose tree of the root node field and its nested
  # fields. We recurse down the rose tree and perform a query for the
  # associated entities for each field.
  defp do_run(structs, repo, {field, sub_fields}) do
    # TODO: Make this use the new Ecto.Model.assoc/2.
    module = hd(structs).__struct__

    # TODO: What if reflections is nil?!
    refl   = module.__schema__(:association, field)

    should_sort? = should_sort?(structs, module, refl)

    # Query for the associated entities
    if query = preload_query(structs, refl) do
      associated = repo.all(query)

      # Recurse down nested fields
      associated = Enum.reduce(sub_fields, associated, &do_run(&2, repo, &1))

      if should_sort? do
        # Save the structs old indices and then sort by primary_key or foreign_key
        # depending on the association type
        {structs, indices} =
          structs
          |> Stream.with_index
          |> sort(refl)
          |> :lists.unzip
      end

      # Put the associated entities on the association of the parent
      merged = merge(structs, associated, refl, [], [])

      if should_sort? do
        # Restore ordering of entities given to the preloader
        merged =
          indices
          |> :lists.zip(merged)
          |> Enum.sort()
          |> Enum.map(&elem(&1, 1))
      end

      merged
    else
      # Set the association as loaded but empty
      Enum.map(structs, &set_loaded(&1, refl, []))
    end
  end

  defp preload_query(structs, refl) do
    owner_key = refl.owner_key
    assoc_key = refl.assoc_key

    ids =
      for struct <- structs,
          key = Map.fetch!(struct, owner_key),
          do: key

    if ids != [] do
         Q.from x in refl.assoc,
         where: field(x, ^assoc_key) in ^ids,
      order_by: field(x, ^assoc_key)
    end
  end

  ## MERGE ##

  defp merge([], [_], _refl, acc, []) do
    Enum.reverse(acc)
  end

  defp merge(structs, [], refl, acc1, acc2) do
    [struct|structs] = structs

    # Store accumulated association on next struct
    struct = set_loaded(struct, refl, Enum.reverse(acc2))

    # Set remaining structs loaded associations to empty lists
    structs = Enum.map(structs, &set_loaded(&1, refl, []))

    Enum.reverse(acc1, [struct|structs])
  end

  defp merge(structs, assocs, refl, acc1, acc2) do
    match(structs, assocs, refl, acc1, acc2)
  end

  defp match([struct|structs], [assoc|assocs], %BelongsTo{} = refl, acc, []) do
    case compare(struct, assoc, refl) do
      # Struct and association match so store association on struct,
      # association may match more structs so keep it
      :eq ->
        struct = set_loaded(struct, refl, [assoc])
        merge(structs, [assoc|assocs], refl, [struct|acc], [])
      # Go to next association
      :gt ->
        merge([struct|structs], assocs, refl, acc, [])
      # Go to next struct, no association matched it so store nil
      # in association
      :lt ->
        struct = set_loaded(struct, refl, [])
        merge(structs, [assoc|assocs], refl, [struct|acc], [])
    end
  end

  defp match([struct|structs], [assoc|assocs], refl, acc1, acc2) do
    if compare(struct, assoc, refl) == :eq do
      # Struct and association match so save association in accumulator, more
      # associations may match the same struct
      merge([struct|structs], assocs, refl, acc1, [assoc|acc2])
    else
      # Struct and association doesnt match so store previously accumulated
      # associations on struct, move onto the next struct and reset acc
      struct = set_loaded(struct, refl, Enum.reverse(acc2))
      merge(structs, [assoc|assocs], refl, [struct|acc1], [])
    end
  end

  defp compare(struct, assoc, refl) do
    struct_id = Map.get(struct, refl.owner_key)
    assoc_id  = Map.get(assoc, refl.assoc_key)
    cond do
      struct_id == assoc_id -> :eq
      struct_id > assoc_id  -> :gt
      struct_id < assoc_id  -> :lt
    end
  end

  ## NORMALIZER ##

  defp normalize(preload, assocs, original) do
    Enum.map(List.wrap(preload), &normalize_each(&1, assocs, original))
  end

  defp normalize_each({atom, list}, assocs, original) when is_atom(atom) do
    no_assoc!(assocs, atom)
    {atom, normalize(list, assocs, original)}
  end

  defp normalize_each(atom, assocs, _original) when is_atom(atom) do
    no_assoc!(assocs, atom)
    {atom, []}
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

  ## SORTING ##

  defp should_sort?(structs, module, refl) do
    key   = refl.owner_key
    first = hd(structs) |> Map.get(key)

    Enum.reduce(structs, {first, false}, fn struct, {current, sort?} ->
      if struct.__struct__ != module do
        raise ArgumentError, "all models have to be of the same type for preload"
      end

      next = Map.fetch!(struct, key)
      {next, sort? or next < current}
    end) |> elem(1)
  end

  defp sort(structs, refl) do
    key = refl.owner_key
    Enum.sort(structs, fn {struct1, _}, {struct2, _} ->
      Map.fetch!(struct1, key) < Map.fetch!(struct2, key)
    end)
  end

  ## HELPERS

  defp extract([[nil|_]|t2]), do: extract(t2)
  defp extract([[h|_]|t2]),   do: [h|extract(t2)]
  defp extract([]),           do: []

  defp unextract(structs, [[nil|_]=h2|t2]),  do: [h2|unextract(structs, t2)]
  defp unextract([h1|structs], [[_|t1]|t2]), do: [[h1|t1]|unextract(structs, t2)]
  defp unextract([], []),                    do: []

  # TODO: Do not hardcode reflection
  defp set_loaded(struct, refl, loaded) do
    unless refl.__struct__ == Ecto.Associations.HasMany do
      loaded = List.first(loaded)
    end
    Map.put(struct, refl.field, loaded)
  end
end
