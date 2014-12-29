defmodule Ecto.Associations.Preloader do
  @moduledoc """
  This module provides assoc selector merger.
  """

  alias Ecto.Associations.BelongsTo
  require Ecto.Query, as: Q

  @doc """
  Loads all associations on the result set.

  `fields` is a list of fields that can be nested in rose tree
  structure:

      node :: {atom, [node | atom]}

  `pos` is an indice into a tuple or a list that locates
  the preloaded model. If nil, it means the model is not
  nested inside any other data structure.

  See `Ecto.Query.preload/2`.
  """
  @spec run([Ecto.Model.t], atom, [atom | tuple], [non_neg_integer]) :: [Ecto.Model.t]
  def run(original, repo, fields, pos \\ nil)

  def run([], _repo, _fields, _pos) do
    []
  end

  def run(original, _repo, [], _pos) do
    original
  end

  def run(original, repo, fields, pos) do
    fields  = normalize(fields, fields)
    structs = extract(original, pos)
    structs = Enum.reduce(fields, structs, &do_run(&2, repo, &1))
    unextract(structs, original, pos)
  end

  # Receives a list of model struct to preload the given association fields
  # on. The fields given are a rose tree of the root node field and its nested
  # fields. We recurse down the rose tree and perform a query for the
  # associated entities for each field.
  defp do_run(structs, repo, {field, sub_fields}) do
    # TODO: Make this use the new Ecto.Model.assoc/2.
    # We just need to prune nils before-hand.
    module = hd(structs).__struct__
    # TODO: What if reflections is nil?!
    refl   = module.__schema__(:association, field)
    should_sort? = should_sort?(structs, refl)

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
          struct != nil,
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
    # Store accumulated association on next struct
    [struct|structs] = structs
    struct = set_loaded(struct, refl, Enum.reverse(acc2))

    # Set remaining structs loaded associations to empty lists
    structs = Enum.map(structs, fn struct ->
      if struct, do: set_loaded(struct, refl, []), else: struct
    end)

    Enum.reverse(acc1, [struct|structs])
  end

  defp merge([struct|structs], assocs, refl, acc1, acc2) do
    # Ignore nil structs, they may be nil depending on the join qualifier
    if is_nil(struct) do
      merge(structs, assocs, refl, [nil|acc1], acc2)
    else
      match([struct|structs], assocs, refl, acc1, acc2)
    end
  end

  defp match([struct|structs], [assoc|assocs], %BelongsTo{} = refl, acc, []) do
    case compare(struct, assoc, refl) do
      # Record and association match so store association on struct,
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

  # Compare struct and association to see if they match
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

  defp normalize(preload, original) do
    Enum.map(List.wrap(preload), &normalize_each(&1, original))
  end

  defp normalize_each({atom, list}, original) when is_atom(atom) do
    {atom, normalize(list, original)}
  end

  defp normalize_each(atom, _original) when is_atom(atom) do
    {atom, []}
  end

  defp normalize_each(other, original) do
    raise ArgumentError, "invalid preload `#{inspect other}` in `#{inspect original}`. " <>
                         "preload expects an atom, a (nested) keyword or a (nested) list of atoms"
  end

  ## SORTING ##

  defp should_sort?(structs, refl) do
    key   = refl.owner_key
    first = hd(structs)

    Enum.reduce(structs, {first, false}, fn struct, {last, sort?} ->
      if last && struct && struct.__struct__ != last.__struct__ do
        raise ArgumentError, "all models have to be of the same type for preload"
      end

      sort? = sort? || (last && struct && Map.get(last, key) > Map.get(struct, key))
      {struct, sort?}
    end) |> elem(1)
  end

  defp sort(structs, refl) do
    key = refl.owner_key
    Enum.sort(structs, fn {struct1, _}, {struct2, _} ->
      !! (struct1 && struct2 && Map.get(struct1, key) < Map.get(struct2, key))
    end)
  end

  ## EXTRACT / UNEXTRACT ##

  # Extract structs from their data structure
  defp extract(original, nil), do: original
  defp extract(original, pos), do: Enum.map(original, &get_at_pos(&1, pos))

  # Put structs back into their original data structure
  defp unextract(structs, _original, nil), do: structs
  defp unextract(structs, original, pos) do
    :lists.zipwith(fn struct, inner ->
      put_at_pos(struct, inner, pos)
    end, structs, original)
  end

  defp get_at_pos(tuple, pos) when is_tuple(tuple),
    do: elem(tuple, pos)
  defp get_at_pos(list, pos) when is_list(list),
    do: Enum.fetch!(list, pos)

  defp put_at_pos(struct, tuple, pos) when is_tuple(tuple),
    do: put_elem(tuple, pos, struct)
  defp put_at_pos(struct, list, pos) when is_list(list),
    do: List.update_at(list, pos, struct)

  # TODO: Do not hardcode reflection
  defp set_loaded(struct, refl, loaded) do
    unless refl.__struct__ == Ecto.Associations.HasMany do
      loaded = List.first(loaded)
    end
    Map.put(struct, refl.field, loaded)
  end
end
