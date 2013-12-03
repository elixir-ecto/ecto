defmodule Ecto.Associations.Preloader do
  @moduledoc """
  This module provides assoc selector merger.
  """

  alias Ecto.Reflections.HasOne
  alias Ecto.Reflections.HasMany
  alias Ecto.Reflections.BelongsTo
  alias Ecto.Query.Util
  require Ecto.Query, as: Q

  @doc """
  Loads all associations on the result set according to the given fields.
  See `Ecto.Query.preload/2`.
  """
  def run(original, repo, fields, pos // [])

  def run([], _repo, _fields, _pos), do: []

  def run(original, _repo, [], _pos), do: original

  def run(original, repo, fields, pos) do
    fields = Ecto.Query.PreloadBuilder.normalize(fields)
    records = extract(original, pos)
    records = Enum.reduce(fields, records, &do_run(&2, repo, &1))
    unextract(records, original, pos)
  end

  defp do_run(records, repo, field) do
    case field do
      { name, sub_fields } -> sub_fields = List.wrap(sub_fields)
      name -> sub_fields = []
    end

    record = Enum.first(records)
    module = elem(record, 0)
    refl = module.__entity__(:association, name)
    query = preload_query(refl, records)
    associated = repo.all(query)

    # Recurse down nested fields
    associated = Enum.reduce(sub_fields, associated, &do_run(&2, repo, &1))

    # TODO: Make sure all records are the same entity
    # TODO: Check if we need actually need to sort for performance,
    #       combine with above

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
  end

  defp preload_query(refl, records)
      when is_record(refl, HasMany) or is_record(refl, HasOne) do
    pk  = refl.primary_key
    fk  = refl.foreign_key
    ids = Enum.filter_map(records, &(&1), &apply(&1, pk, []))

       Q.from x in refl.associated,
       where: field(x, ^fk) in ^ids,
    order_by: field(x, ^fk)
  end

  defp preload_query(BelongsTo[] = refl, records) do
    fun = &apply(&1, refl.foreign_key, [])
    ids = Enum.filter_map(records, fun, fun)
    pk = refl.primary_key

       Q.from x in refl.associated,
       where: field(x, ^pk) in ^ids,
    order_by: field(x, ^pk)
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
    record_id = apply(record, Util.record_key(refl), [])
    assoc_id = apply(assoc, Util.assoc_key(refl), [])
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
    key = Util.record_key(refl)
    Enum.sort(records, fn { record1, _ }, { record2, _ } ->
      !! (record1 && record2 && apply(record1, key, []) < apply(record2, key, []))
    end)
  end

  defp unsort(records) do
    Enum.sort(records, fn { _, ix1 }, { _, ix2 } ->
      ix1 < ix2
    end)
  end


  ## EXTRACT / UNEXTRACT ##

  # Extract records from their data structure, see get_at_pos
  defp extract(original, pos) do
    if pos == [] do
      original
    else
      Enum.map(original, &get_at_pos(&1, pos))
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
    set_elem(tuple, ix, set_at_pos(elem, pos, value))
  end

  defp set_at_pos(list, [ix|pos], value) when is_list(list) do
    List.update_at(list, ix, &set_at_pos(&1, pos, value))
  end
end
