defmodule Ecto.Preloader do
  @moduledoc false

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util
  alias Ecto.Reflections.HasOne
  alias Ecto.Reflections.HasMany

  def run(repo, original, name, pos // []) do
    if pos == [] do
      records = original
    else
      records = Enum.map(original, &get_from_pos(&1, pos))
    end

    record = Enum.first(records)
    module = elem(record, 0)
    refl = module.__ecto__(:association, name)

    ids = Enum.map(records, &(&1.primary_key))
    where_expr = quote do &0.unquote(refl.foreign_key) in unquote(ids) end
    where = QueryExpr[expr: where_expr]
    order_bys = QueryExpr[expr: [ { nil, quote do &0 end, refl.foreign_key } ]]
    query = Query[from: refl.associated, wheres: [where], order_bys: [order_bys]]

    associated = repo.all(query)

    # TODO: Make sure all records are the same entity
    records = records
      |> Stream.with_index
      |> Enum.sort(&cmp_record/2)

    # TODO: Check the type of association has_many / has_one / belongs_to
    records = combine(records, associated, refl, [], [])
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

  defp combine(records, [], refl, acc1, acc2) do
    [record|records] = records
    record = set_loaded(record, refl, Enum.reverse(acc2))

    records = Enum.map(records, fn record ->
      set_loaded(record, refl, [])
    end)
    acc1 ++ [record|records]
  end

  defp combine([record|records], [assoc|assocs], refl, acc1, acc2) do
    if primary_key(record) == apply(assoc, refl.foreign_key, []) do
      combine([record|records], assocs, refl, acc1, [assoc|acc2])
    else
      record = set_loaded(record, refl, Enum.reverse(acc2))
      combine(records, [assoc|assocs], refl, [record|acc1], [])
    end
  end

  defp primary_key({ record, _ }), do: record.primary_key

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
