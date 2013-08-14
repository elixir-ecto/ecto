defmodule Ecto.Preloader do
  @moduledoc false

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util

  # TODO: Position in tuple
  def run(repo, records, field) do
    # TODO: Make sure all records are the same entity
    records = Enum.sort(records, &(&1.primary_key < &2.primary_key))
    ids = Enum.map(records, &(&1.primary_key))

    record = Enum.first(records)
    [module|_] = tuple_to_list(record)
    refl = module.__ecto__(:association, field)
    # TODO: Check the type of association has_many / has_one / belongs_to

    where_expr = quote do &0.unquote(refl.foreign_key) in unquote(ids) end
    where = QueryExpr[expr: where_expr]
    order_bys = [
      { nil, quote do &0 end, refl.foreign_key },
      { nil, quote do &0 end, refl.associated.__ecto__(:primary_key) } ]
    query = Query[from: refl.associated, wheres: [where], order_bys: [order_bys]]

    assocs = repo.all(query)
    combine(records, assocs, field, refl.foreign_key, [], [])
  end

  defp combine(records, [], field, _fk, acc1, acc2) do
    [record|records] = records
    association = apply(record, field, [])
    association = association.__ecto__(:loaded, Enum.reverse(acc2))
    record = apply(record, field, [association])

    records = Enum.map(records, fn record ->
      association = apply(record, field, [])
      association = association.__ecto__(:loaded, [])
      apply(record, field, [association])
    end)
    Enum.reverse(acc1) ++ [record|records]
  end

  defp combine([], _, _field, _fk, _acc1, _acc2) do
    throw :oops # TODO
  end

  defp combine([record|records], [assoc|assocs], field, fk, acc1, acc2) do
    if record.primary_key == apply(assoc, fk, []) do
      combine([record|records], assocs, field, fk, acc1, [assoc|acc2])
    else
      association = apply(record, field, [])
      association = association.__ecto__(:loaded, Enum.reverse(acc2))
      record = apply(record, field, [association])

      combine(records, [assoc|assocs], field, fk, [record|acc1], [])
    end
  end
end
