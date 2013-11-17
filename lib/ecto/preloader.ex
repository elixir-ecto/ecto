defmodule Ecto.Preloader do
  @moduledoc false

  alias Ecto.Reflections.HasOne
  alias Ecto.Reflections.BelongsTo

  def run(repo, original, name, pos // [])

  def run(_repo, [], _name, _pos), do: []

  def run(repo, original, name, pos) do
    records = extract(original, pos)

    record = Enum.first(records)
    module = elem(record, 0)
    refl = module.__entity__(:association, name)
    query = Ecto.Associations.preload_query(refl, records)
    associated = repo.all(query)

    # TODO: Make sure all records are the same entity

    # Save the records old indicies and then sort by primary_key or foreign_key
    # depending on the association type
    { records, indicies } = records
    |> Stream.with_index
    |> sort(refl)
    |> :lists.unzip

    combined = case refl do
      BelongsTo[] ->
        combine_belongs(records, associated, refl, [])
      _ ->
        combine_has(records, associated, refl, [], [])
    end

    # Restore ordering given to the preloader and put back records into
    # original data structure
    combined
    |> :lists.zip(indicies)
    |> unsort()
    |> Enum.map(&elem(&1, 0))
    |> unextract(original, pos)
  end


  ## COMBINE HAS_MANY / HAS_ONE ##

  defp combine_has(records, [], refl, acc1, acc2) do
    # Store accumulated association on next record
    [record|records] = records
    record = set_loaded(record, refl, Enum.reverse(acc2))

    # Set remaining records loaded assocations to empty lists
    records = Enum.map(records, fn record ->
      if record, do: set_loaded(record, refl, []), else: record
    end)
    Enum.reverse(acc1) ++ [record|records]
  end

  defp combine_has([record|records], [assoc|assocs], refl, acc1, acc2) do
    cond do
      # Ignore nil records, they may be nil depending on the join qualifier
      nil?(record) ->
        combine_has(records, [assoc|assocs], refl, [nil|acc1], acc2)
      # Record and association match so save association in accumulator, more
      # associations may match the same record
      compare(record, assoc, refl) == :eq ->
        combine_has([record|records], assocs, refl, acc1, [assoc|acc2])
      # Record and association doesnt match so store previously accumulated
      # associations on record, move onto the next record and reset acc
      true ->
        record = set_loaded(record, refl, Enum.reverse(acc2))
        combine_has(records, [assoc|assocs], refl, [record|acc1], [])
    end
  end


  ## COMBINE BELONGS_TO ##

  defp combine_belongs([], [_], _refl, acc) do
    Enum.reverse(acc)
  end

  defp combine_belongs(records, [], refl, acc) do
    # Set remaining records loaded assocations to nil
    records = Enum.map(records, fn record ->
      if record, do: set_loaded(record, refl, nil), else: record
    end)
    Enum.reverse(acc) ++ records
  end

  defp combine_belongs([record|records], [assoc|assocs], refl, acc) do
    if nil?(record) do
      # Ignore nil records, they may be nil depending on the join qualifier
      combine_belongs(records, [assoc|assocs], refl, [nil|acc])
    else
      case compare(record, assoc, refl) do
        # Record and association match so store association on record,
        # association may match more records so keep it
        :eq ->
          record = set_loaded(record, refl, assoc)
          combine_belongs(records, [assoc|assocs], refl, [record|acc])
        # Go to next association
        :gt ->
          combine_belongs([record|records], assocs, refl, acc)
        # Go to next record, no association matched it so store nil
        # in association
        :lt ->
          record = set_loaded(record, refl, nil)
          combine_belongs(records, [assoc|assocs], refl, [record|acc])
      end
    end
  end


  ## COMMON UTILS ##

  # Compare record and association to see if they match
  defp compare(record, assoc, refl) do
    record_id = apply(record, record_key(refl), [])
    assoc_id = apply(assoc, assoc_key(refl), [])
    cond do
      record_id == assoc_id -> :eq
      record_id > assoc_id -> :gt
      record_id < assoc_id -> :lt
    end
  end

  # Set the loaded value on the association of the given record
  defp set_loaded(record, refl, value) do
    if is_record(refl, HasOne), do: value = Enum.first(value)
    field = refl.field
    association = apply(record, field, [])
    association = association.__assoc__(:loaded, value)
    apply(record, field, [association])
  end


  ## SORTING ##

  defp sort(records, refl) do
    key = record_key(refl)
    Enum.sort(records, fn { record1, _ }, { record2, _ } ->
      !! (record1 && record2 && apply(record1, key, []) < apply(record2, key, []))
    end)
  end

  defp unsort(records) do
    Enum.sort(records, fn { _, ix1 }, { _, ix2 } ->
      ix1 < ix2
    end)
  end

  defp record_key(BelongsTo[] = refl), do: refl.foreign_key
  defp record_key(refl), do: refl.primary_key

  defp assoc_key(BelongsTo[] = refl), do: refl.primary_key
  defp assoc_key(refl), do: refl.foreign_key


  ## EXTRACT / UNEXTRACT ##

  # Extract records from their data structure, see get_from_pos
  defp extract(original, pos) do
    if pos == [] do
      original
    else
      Enum.map(original, &get_from_pos(&1, pos))
    end
  end

  # Put records back into their original data structure
  defp unextract(records, original, pos) do
    if pos == [] do
      records
    else
      records
      |> :lists.zip(original)
      |> Enum.map(fn { rec, orig } -> set_at_pos(orig, pos, rec) end)
    end
  end

  # The record that needs associations preloaded on it can be nested inside
  # tuples and lists. We retrieve and set the record inside the structure with
  # the help of a list of indicies into tuples and lists.
  # { x, [ y, z, { RECORD, p } ] } #=> indicies: [ 1, 2, 0 ]
  defp get_from_pos(value, []), do: value

  defp get_from_pos(tuple, [ix|pos]) when is_tuple(tuple) do
    elem(tuple, ix) |> get_from_pos(pos)
  end

  defp get_from_pos(list, [ix|pos]) when is_list(list) do
    Enum.at(list, ix) |> get_from_pos(pos)
  end

  defp set_at_pos(_other, [], value) do
    value
  end

  defp set_at_pos(tuple, [ix|pos], value) when is_tuple(tuple) do
    elem = elem(tuple, ix)
    set_elem(tuple, ix, set_at_pos(elem, pos, value))
  end

  defp set_at_pos(list, [ix|pos], value) when is_list(list) do
    update_at(list, ix, &set_at_pos(&1, pos, value))
  end

  # TODO: Add to List/Enum module?
  # Update element at index location in list with given function
  defp update_at(list, index, fun) do
    if index < 0 do
      do_update_at(list, length(list) + index, fun)
    else
      do_update_at(list, index, fun)
    end
  end

  defp do_update_at([value|list], index, fun) when index <= 0 do
    [ fun.(value) | list ]
  end

  defp do_update_at([h|t], index, fun) do
    [ h | do_update_at(t, index - 1, fun) ]
  end
end
