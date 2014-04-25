defmodule Ecto.Associations.Preloader do
  @moduledoc """
  This module provides assoc selector merger.
  """

  alias Ecto.Reflections.BelongsTo
  alias Ecto.Associations
  require Ecto.Query, as: Q

  @doc """
  Loads all associations on the result set according to the given fields.
  `fields` is a list of fields that can be nested in rose tree structure:
  `node :: { atom, [node | atom] }` (see `Ecto.Query.PreloadBuilder.normalize/1`).
  `pos` is a list of indices into tuples and lists that locate the concerned
  entity.

  See `Ecto.Query.preload/2`.
  """
  @spec run([Record.t], atom, [atom | tuple], [non_neg_integer]) :: [Record.t]
  def run(original, repo, fields, pos \\ [])

  def run(original, _repo, [], _pos), do: original

  def run(original, repo, fields, pos) do
    fields = Ecto.Query.PreloadBuilder.normalize(fields)
    records = extract(original, pos)
    records = Enum.reduce(fields, records, &do_run(&2, repo, &1))
    unextract(records, original, pos)
  end

  # Receives a list of entity records to preload the given association fields
  # on. The fields given are a rose tree of the root node field and its nested
  # fields. We recurse down the rose tree and perform a query for the
  # associated entities for each field.
  defp do_run([], _repo, _field), do: []

  defp do_run(records, repo, { field, sub_fields }) do
    record = List.first(records)
    module = elem(record, 0)
    refl = module.__entity__(:association, field)
    should_sort? = should_sort?(records, refl)

    # Query for the associated entities
    if query = preload_query(records, refl) do
      associated = repo.all(query)

      # Recurse down nested fields
      associated = Enum.reduce(sub_fields, associated, &do_run(&2, repo, &1))

      if should_sort? do
        # Save the records old indices and then sort by primary_key or foreign_key
        # depending on the association type
        { records, indices } = records
        |> Stream.with_index
        |> sort(refl)
        |> :lists.unzip
      end

      # Put the associated entities on the association of the parent
      merged = merge(records, associated, refl, [], [])

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

  defp preload_query(records, refl) do
    key       = refl.key
    assoc_key = refl.assoc_key
    record    = Enum.find(records, & &1)
    module    = if record, do: elem(record, 0)
    type      = if module, do: module.__entity__(:field_type, key)

    ids = Enum.reduce(records, [], fn record, acc ->
      if record && (key = apply(record, key, [])), do: [key|acc], else: acc
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

  defp merge(records, [], refl, acc1, acc2) do
    # Store accumulated association on next record
    [record|records] = records
    record = Associations.set_loaded(record, refl, Enum.reverse(acc2))

    # Set remaining records loaded associations to empty lists
    records = Enum.map(records, fn record ->
      if record, do: Associations.set_loaded(record, refl, []), else: record
    end)
    Enum.reverse(acc1) ++ [record|records]
  end

  defp merge([record|records], assocs, refl, acc1, acc2) do
    # Ignore nil records, they may be nil depending on the join qualifier
    if nil?(record) do
      merge(records, assocs, refl, [nil|acc1], acc2)
    else
      match([record|records], assocs, refl, acc1, acc2)
    end
  end

  defp match([record|records], [assoc|assocs], BelongsTo[] = refl, acc, []) do
    case compare(record, assoc, refl) do
      # Record and association match so store association on record,
      # association may match more records so keep it
      :eq ->
        record = Associations.set_loaded(record, refl, [assoc])
        merge(records, [assoc|assocs], refl, [record|acc], [])
      # Go to next association
      :gt ->
        merge([record|records], assocs, refl, acc, [])
      # Go to next record, no association matched it so store nil
      # in association
      :lt ->
        record = Associations.set_loaded(record, refl, [])
        merge(records, [assoc|assocs], refl, [record|acc], [])
    end
  end

  defp match([record|records], [assoc|assocs], refl, acc1, acc2) do
    if compare(record, assoc, refl) == :eq do
      # Record and association match so save association in accumulator, more
      # associations may match the same record
      merge([record|records], assocs, refl, acc1, [assoc|acc2])
    else
      # Record and association doesnt match so store previously accumulated
      # associations on record, move onto the next record and reset acc
      record = Associations.set_loaded(record, refl, Enum.reverse(acc2))
      merge(records, [assoc|assocs], refl, [record|acc1], [])
    end
  end

  # Compare record and association to see if they match
  defp compare(record, assoc, refl) do
    record_id = apply(record, refl.key, [])
    assoc_id = apply(assoc, refl.assoc_key, [])
    cond do
      record_id == assoc_id -> :eq
      record_id > assoc_id -> :gt
      record_id < assoc_id -> :lt
    end
  end


  ## SORTING ##

  defp should_sort?(records, refl) do
    key = refl.key
    first = List.first(records)

    Enum.reduce(records, { first, false }, fn record, { last, sort? } ->
      if last && record && elem(record, 0) != elem(last, 0) do
        raise ArgumentError, message: "all entities have to be of the same type"
      end

      sort? = sort? || (last && record && apply(last, key, []) > apply(record, key, []))
      { record, sort? }
    end) |> elem(1)
  end

  defp sort(records, refl) do
    key = refl.key
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
  # the help of a list of indices into tuples and lists.
  # { x, [ y, z, { RECORD, p } ] } #=> indices: [ 1, 2, 0 ]
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
