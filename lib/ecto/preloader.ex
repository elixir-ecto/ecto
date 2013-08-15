defmodule Ecto.Preloader do
  @moduledoc false

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util
  alias Ecto.Reflections.HasMany

  # TODO: Position in tuple
  def run(repo, records, name) do
    record = Enum.first(records)
    module = elem(record, 0)
    refl = module.__ecto__(:association, name)

    # TODO: Make sure all records are the same entity
    records = records
      |> Stream.with_index
      |> Enum.sort(&cmp_record/2)
    ids = Enum.map(records, &primary_key/1)

    # TODO: Check the type of association has_many / has_one / belongs_to

    where_expr = quote do &0.unquote(refl.foreign_key) in unquote(ids) end
    where = QueryExpr[expr: where_expr]
    order_bys = [ { nil, quote do &0 end, refl.foreign_key } ]
    query = Query[from: refl.associated, wheres: [where], order_bys: [order_bys]]

    assocs = repo.all(query)
    combine(records, assocs, refl, [], [])
      |> Enum.sort(&cmp_prev_record/2)
      |> Enum.map(&elem(&1, 0))
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

  defp set_loaded({ record, ix }, HasMany[field: field], value) do
    association = apply(record, field, [])
    association = association.__loaded__(value)
    { apply(record, field, [association]), ix }
  end
end
