defmodule Ecto.Associations.Preloader do
  @moduledoc """
  This module provides assoc selector merger.
  """

  alias Ecto.Reflections.BelongsTo
  require Ecto.Query, as: Q

  @doc """
  Loads all associations on the result set according to the given fields.
  `fields` is a list of fields that can be nested in rose tree structure:
  `node :: {atom, [node | atom]}` (see `Ecto.Query.PreloadBuilder.normalize/1`).
  `pos` is a list of indices into tuples and lists that locate the concerned
  model.

  See `Ecto.Query.preload/2`.
  """
  @spec run([Ecto.Model.t], atom, [atom | tuple], [non_neg_integer]) :: [Ecto.Model.t]
  def run(original, repo, fields, pos \\ [])

  def run(original, _repo, [], _pos), do: original

  def run(original, repo, fields, pos) do
    fields = Ecto.Query.PreloadBuilder.normalize(fields)
    structs = extract(original, pos)
    structs = Enum.reduce(fields, structs, &do_run(&2, repo, &1))
    unextract(structs, original, pos)
  end

  # Receives a list of model struct to preload the given association fields
  # on. The fields given are a rose tree of the root node field and its nested
  # fields. We recurse down the rose tree and perform a query for the
  # associated entities for each field.
  defp do_run([], _repo, _field), do: []

  defp do_run(structs, repo, {field, sub_fields}) do
    struct = List.first(structs)
    module = struct.__struct__
    refl = module.__schema__(:association, field)
    should_sort? = should_sort?(structs, refl)

    # Query for the associated entities
    if query = preload_query(structs, refl) do
      associated = repo.all(query)

      # Recurse down nested fields
      associated = Enum.reduce(sub_fields, associated, &do_run(&2, repo, &1))

      if should_sort? do
        # Save the structs old indices and then sort by primary_key or foreign_key
        # depending on the association type
        {structs, indices} = structs
        |> Stream.with_index
        |> sort(refl)
        |> :lists.unzip
      end

      # Put the associated entities on the association of the parent
      merged = merge(structs, associated, refl, [], [])

      if should_sort? do
        # Restore ordering of entities given to the preloader
        merged = merged
        |> :lists.zip(indices)
        |> unsort()
        |> Enum.map(&elem(&1, 0))
      end

      merged
    else
      []
    end
  end

  defp preload_query(structs, refl) do
    key       = refl.key
    assoc_key = refl.assoc_key
    struct    = Enum.find(structs, & &1)
    module    = if struct, do: struct.__struct__
    type      = if module, do: module.__schema__(:field_type, key)

    ids = Enum.reduce(structs, [], fn struct, acc ->
      if struct && (key = Map.get(struct, key)), do: [key|acc], else: acc
    end)

    if ids != [] do
         Q.from x in refl.associated,
         where: field(x, ^assoc_key) in array(^ids, ^type),
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
    Enum.reverse(acc1) ++ [struct|structs]
  end

  defp merge([struct|structs], assocs, refl, acc1, acc2) do
    # Ignore nil structs, they may be nil depending on the join qualifier
    if nil?(struct) do
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
      # Record and association match so save association in accumulator, more
      # associations may match the same struct
      merge([struct|structs], assocs, refl, acc1, [assoc|acc2])
    else
      # Record and association doesnt match so store previously accumulated
      # associations on struct, move onto the next struct and reset acc
      struct = set_loaded(struct, refl, Enum.reverse(acc2))
      merge(structs, [assoc|assocs], refl, [struct|acc1], [])
    end
  end

  # Compare struct and association to see if they match
  defp compare(struct, assoc, refl) do
    record_id = Map.get(struct, refl.key)
    assoc_id = Map.get(assoc, refl.assoc_key)
    cond do
      record_id == assoc_id -> :eq
      record_id > assoc_id  -> :gt
      record_id < assoc_id  -> :lt
    end
  end


  ## SORTING ##

  defp should_sort?(structs, refl) do
    key = refl.key
    first = List.first(structs)

    Enum.reduce(structs, {first, false}, fn struct, {last, sort?} ->
      if last && struct && struct.__struct__ != last.__struct__ do
        raise ArgumentError, message: "all models have to be of the same type"
      end

      sort? = sort? || (last && struct && Map.get(last, key) > Map.get(struct, key))
      {struct, sort?}
    end) |> elem(1)
  end

  defp sort(structs, refl) do
    key = refl.key
    Enum.sort(structs, fn {struct1, _}, {struct2, _} ->
      !! (struct1 && struct2 && Map.get(struct1, key) < Map.get(struct2, key))
    end)
  end

  defp unsort(structs) do
    Enum.sort(structs, fn {_, ix1}, {_, ix2} ->
      ix1 < ix2
    end)
  end


  ## EXTRACT / UNEXTRACT ##

  # Extract structs from their data structure, see get_at_pos
  defp extract(original, pos) do
    if pos == [] do
      original
    else
      Enum.map(original, &get_at_pos(&1, pos))
    end
  end

  # Put structs back into their original data structure
  defp unextract(structs, original, pos) do
    if pos == [] do
      structs
    else
      structs
      |> :lists.zip(original)
      |> Enum.map(fn {rec, orig} -> set_at_pos(orig, pos, rec) end)
    end
  end

  # The struct that needs associations preloaded on it can be nested inside
  # tuples and lists. We retrieve and set the struct inside the structure with
  # the help of a list of indices into tuples and lists.
  # {x, [ y, z, {STRUCT, p} ]} #=> indices: [ 1, 2, 0 ]
  defp get_at_pos(value, []), do: value

  defp get_at_pos(tuple, [ix|pos]) when is_tuple(tuple) do
    elem(tuple, ix) |> get_at_pos(pos)
  end

  defp get_at_pos(list, [ix|pos]) when is_list(list) do
    Enum.at(list, ix) |> get_at_pos(pos)
  end

  defp set_at_pos(_other, [], value) do
    value
  end

  defp set_at_pos(tuple, [ix|pos], value) when is_tuple(tuple) do
    elem = elem(tuple, ix)
    put_elem(tuple, ix, set_at_pos(elem, pos, value))
  end

  defp set_at_pos(list, [ix|pos], value) when is_list(list) do
    List.update_at(list, ix, &set_at_pos(&1, pos, value))
  end

  defp set_loaded(struct, refl, loaded) do
    unless refl.__struct__ == Ecto.Reflections.HasMany do
      loaded = List.first(loaded)
    end
    Ecto.Associations.load(struct, refl.field, loaded)
  end
end
