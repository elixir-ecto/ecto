defmodule Ecto.Preloader do
  @moduledoc false

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util
  alias Ecto.Reflections.HasOne
  alias Ecto.Reflections.HasMany
  alias Ecto.Reflections.BelongsTo

  def run(repo, original, name, pos // []) do
    if pos == [] do
      records = original
    else
      records = Enum.map(original, &get_from_pos(&1, pos))
    end

    record = Enum.first(records)
    module = elem(record, 0)
    refl = module.__ecto__(:association, name)
    query = Ecto.Associations.preload_query(refl, records)
    associated = repo.all(query)

    # TODO: Make sure all records are the same entity
    records = records
      |> Stream.with_index
      |> Enum.sort(&cmp_record/2)

    if match?(BelongsTo[], refl) do
      records = combine_belongs(records, associated, refl, [])
    else
      records = combine_has(records, associated, refl, [], [])
    end

    records = records
      |> Enum.sort(&cmp_prev_record/2)
      |> Enum.map(&elem(&1, 0))

    if pos == [] do
      records
    else
      records
        |> Enum.zip(original)
        |> Enum.map(fn { rec, orig } -> set_at_pos(orig, pos, rec) end)
    end
  end

  defp combine_has(records, [], refl, acc1, acc2) do
    [record|records] = records
    record = set_loaded(record, refl, Enum.reverse(acc2))

    records = Enum.map(records, fn record ->
      set_loaded(record, refl, [])
    end)
    acc1 ++ [record|records]
  end

  defp combine_has([record|records], [assoc|assocs], refl, acc1, acc2) do
    if primary_key(record) == apply(assoc, refl.foreign_key, []) do
      combine_has([record|records], assocs, refl, acc1, [assoc|acc2])
    else
      record = set_loaded(record, refl, Enum.reverse(acc2))
      combine_has(records, [assoc|assocs], refl, [record|acc1], [])
    end
  end

  defp combine_belongs(records, [], _refl, acc) do
    Enum.reverse(acc) ++ records
  end

  defp combine_belongs([record|records], [assoc|assocs], refl, acc) do
    pk = refl.associated.__ecto__(:primary_key)
    if foreign_key(record, refl) == apply(assoc, pk, []) do
      record = set_loaded(record, refl, assoc)
      combine_belongs(records, assocs, refl, [record|acc])
    else
      record = set_loaded(record, refl, nil)
      combine_belongs(records, [assoc|assocs], refl, [record|acc])
    end
  end

  defp primary_key({ record, _ }), do: record.primary_key

  defp foreign_key({ record, _ }, refl), do: apply(record, refl.foreign_key, [])

  defp cmp_record({ record1, _ }, { record2, _ }) do
    record1.primary_key < record2.primary_key
  end

  defp cmp_prev_record({ _, ix1 }, { _, ix2 }) do
    ix1 < ix2
  end

  defp set_loaded(rec, HasOne[field: field], value) do
    value = case value do
      [] -> nil
      [elem] -> elem
    end
    set_loaded(rec, field, value)
  end

  defp set_loaded(rec, HasMany[field: field], value) do
    set_loaded(rec, field, value)
  end

  defp set_loaded(rec, BelongsTo[field: field], value) do
    set_loaded(rec, field, value)
  end

  defp set_loaded({ record, ix }, field, value) do
    association = apply(record, field, [])
    association = association.__ecto__(:loaded, value)
    { apply(record, field, [association]), ix }
  end

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
