defmodule Ecto.Preloader do
  @moduledoc false

  alias Ecto.Reflections.HasOne
  alias Ecto.Reflections.HasMany
  alias Ecto.Reflections.BelongsTo

  def run(repo, original, name, pos // [])

  def run(_repo, [], _name, _pos), do: []

  def run(repo, original, name, pos) do
    # Extract records from their data structure, see get_from_pos
    if pos == [] do
      records = original
    else
      records = Enum.map(original, &get_from_pos(&1, pos))
    end

    record = Enum.first(records)
    module = elem(record, 0)
    refl = module.__entity__(:association, name)
    query = Ecto.Associations.preload_query(refl, records)
    associated = repo.all(query)

    # TODO: Make sure all records are the same entity

    # Save the records old indicies and then sort by primary_key or foreign_key
    # depending on the association type
    records = records
      |> Stream.with_index
      |> Enum.sort(&cmp_record(&1, &2, refl))

    combined = case refl do
      BelongsTo[] ->
        combine_belongs(records, associated, refl, [])
      _ ->
        combine_has(records, associated, refl, [], [])
    end

    # Restore ordering given to the preloader
    records = combined
      |> Enum.sort(&cmp_prev_record/2)
      |> Enum.map(&elem(&1, 0))

    # Put records back into their data structure
    if pos == [] do
      records
    else
      records
        |> Enum.zip(original)
        |> Enum.map(fn { rec, orig } -> set_at_pos(orig, pos, rec) end)
    end
  end

  defp combine_has(records, [], refl, acc1, acc2) do
    # Store accumulated association on next record
    [record|records] = records
    record = set_loaded(record, refl, Enum.reverse(acc2))

    # Set remaining records loaded assocations to empty lists
    records = Enum.map(records, fn record ->
      if elem(record, 0), do: set_loaded(record, refl, []), else: record
    end)
    acc1 ++ [record|records]
  end

  defp combine_has([record|records], [assoc|assocs], refl, acc1, acc2) do
    cond do
      # Ignore nil records, they may be nil depending on the join qualifier
      nil?(elem(record, 0)) ->
        combine_has(records, [assoc|assocs], refl, [nil|acc1], acc2)
      # Record and association match so save association in accumulator, more
      # associations may match the same record
      compare_has(record, assoc, refl) ->
        combine_has([record|records], assocs, refl, acc1, [assoc|acc2])
      # Record and association doesnt match so store previously accumulated
      # associations on record, move onto the next record and reset acc
      true ->
        record = set_loaded(record, refl, Enum.reverse(acc2))
        combine_has(records, [assoc|assocs], refl, [record|acc1], [])
    end
  end

  defp combine_belongs([], [_], _refl, acc) do
    acc
  end

  defp combine_belongs(records, [], refl, acc) do
    # Set remaining records loaded assocations to nil
    records = Enum.map(records, fn record ->
      if elem(record, 0), do: set_loaded(record, refl, nil), else: record
    end)
    acc ++ records
  end

  defp combine_belongs([record|records], [assoc|assocs], refl, acc) do
    if nil?(elem(record, 0)) do
      # Ignore nil records, they may be nil depending on the join qualifier
      combine_belongs(records, [assoc|assocs], refl, [nil|acc])
    else
      case compare_belongs(record, assoc, refl) do
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

  # Compare record and association to see if they match
  defp compare_belongs({ record, _ }, assoc, BelongsTo[] = refl) do
    record_id = apply(record, refl.foreign_key, [])
    assoc_id = apply(assoc, refl.primary_key, [])
    cond do
      record_id == assoc_id -> :eq
      record_id > assoc_id -> :gt
      record_id < assoc_id -> :lt
    end
  end

  # Compare record and association to see if they match
  defp compare_has({ record, _ }, assoc, refl) do
    apply(record, refl.primary_key, []) == apply(assoc, refl.foreign_key, [])
  end

  defp cmp_record({ record1, _ }, { record2, _ }, BelongsTo[] = refl) do
    # BelongsTo sorts by foreign_key
    fk = refl.foreign_key
    !! (record1 && record2 && apply(record1, fk, []) < apply(record2, fk, []))
  end

  defp cmp_record({ record1, _ }, { record2, _ }, refl) do
    # HasOne and HasMany sorts by primary_key
    pk = refl.primary_key
    !! (record1 && record2 && apply(record1, pk, []) < apply(record2, pk, []))
  end

  defp cmp_prev_record({ _, ix1 }, { _, ix2 }) do
    ix1 < ix2
  end

  # Set the loaded value on the association of the given record
  defp set_loaded({ record, ix }, field, value) when is_atom(field) do
    association = apply(record, field, [])
    association = association.__assoc__(:loaded, value)
    { apply(record, field, [association]), ix }
  end

  defp set_loaded(rec, HasMany[field: field], value) do
    set_loaded(rec, field, value)
  end

  defp set_loaded(rec, HasOne[field: field], value) do
    set_loaded(rec, field, Enum.first(value))
  end

  defp set_loaded(rec, BelongsTo[field: field], value) do
    set_loaded(rec, field, value)
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
