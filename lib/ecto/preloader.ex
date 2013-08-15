defmodule Ecto.Preloader do
  @moduledoc false

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util

  # TODO: Position in tuple
  def run(repo, records, name) do
    # TODO: Make sure all records are the same entity
    records = Enum.sort(records, &(&1.primary_key < &2.primary_key))
    ids = Enum.map(records, &(&1.primary_key))

    record = Enum.first(records)
    module = elem(record, 0)
    refl = module.__ecto__(:association, name)
    # TODO: Check the type of association has_many / has_one / belongs_to

    where_expr = quote do &0.unquote(refl.foreign_key) in unquote(ids) end
    where = QueryExpr[expr: where_expr]
    order_bys = [ { nil, quote do &0 end, refl.foreign_key } ]
    query = Query[from: refl.associated, wheres: [where], order_bys: [order_bys]]

    assocs = repo.all(query)
    combine(records, assocs, refl, [], [])
  end

  defp combine(records, [], refl, acc1, acc2) do
    [record|records] = records
    association = apply(record, refl.field, [])
    association = association.__loaded__(Enum.reverse(acc2))
    record = apply(record, refl.field, [association])

    records = Enum.map(records, fn record ->
      association = apply(record, refl.field, [])
      association = association.__loaded__([])
      apply(record, refl.field, [association])
    end)
    Enum.reverse(acc1) ++ [record|records]
  end

  defp combine([record|records], [assoc|assocs], refl, acc1, acc2) do
    if record.primary_key == apply(assoc, refl.foreign_key, []) do
      combine([record|records], assocs, refl, acc1, [assoc|acc2])
    else
      association = apply(record, refl.field, [])
      association = association.__loaded__(Enum.reverse(acc2))
      record = apply(record, refl.field, [association])

      combine(records, [assoc|assocs], refl, [record|acc1], [])
    end
  end
end
