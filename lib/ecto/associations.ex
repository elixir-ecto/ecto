defmodule Ecto.Associations do
  @moduledoc """
  Utilities on associations.
  """

  alias Ecto.Query.Query
  alias Ecto.Query.AssocJoinExpr
  alias Ecto.Query.Util
  alias Ecto.Reflections.HasOne
  alias Ecto.Reflections.HasMany
  alias Ecto.Reflections.BelongsTo
  require Ecto.Query, as: Q

  @doc """
  Returns true if select expression is an assoc selector.
  """
  def assoc_select?({ :assoc, _, [_, _] }), do: true
  def assoc_select?(_), do: false

  @doc """
  Transforms a result set based on the assoc selector, combining the entities
  specified in the assoc selector.
  """
  def transform_result(_expr, [], _query), do: true

  def transform_result({ :assoc, _, [parent, child] }, results, Query[] = query) do
    AssocJoinExpr[expr: join_expr] = Util.find_expr(query, child)
    { :., _, [^parent, field] } = join_expr
    { _source, entity, _model } = query.from
    refl = entity.__entity__(:association, field)

    [{ parent, child }|results] = results
    combine(results, refl, parent, [], [child])
  end

  @doc false
  def create_reflection(type, name, model, module, pk, assoc, fk)
      when type in [:has_many, :has_one] do
    if model do
      model_name = model |> Module.split |> List.last |> String.downcase
    end

    values = [
      owner: module,
      associated: assoc,
      foreign_key: fk || :"#{model_name}_#{pk}",
      primary_key: pk,
      field: :"__#{name}__" ]

    case type do
      :has_many -> Ecto.Reflections.HasMany.new(values)
      :has_one  -> Ecto.Reflections.HasOne.new(values)
    end
  end

  def create_reflection(:belongs_to, name, _model, module, pk, assoc, fk) do
    values = [
      owner: module,
      associated: assoc,
      foreign_key: fk,
      primary_key: pk,
      field: :"__#{name}__" ]
    Ecto.Reflections.BelongsTo.new(values)
  end

  @doc false
  def preload_query(refl, records)
      when is_record(refl, HasMany) or is_record(refl, HasOne) do
    pk  = refl.primary_key
    fk  = refl.foreign_key
    ids = Enum.filter_map(records, &(&1), &apply(&1, pk, []))

       Q.from x in refl.associated,
       where: field(x, ^fk) in ^ids,
    order_by: field(x, ^fk)
  end

  def preload_query(BelongsTo[] = refl, records) do
    fun = &apply(&1, refl.foreign_key, [])
    ids = Enum.filter_map(records, fun, fun)
    pk = refl.primary_key

       Q.from x in refl.associated,
       where: field(x, ^pk) in ^ids,
    order_by: field(x, ^pk)
  end

  ## ASSOCIATION JOIN COMBINER ##

  defp combine([], refl, last_parent, parents, children) do
    children = Enum.reverse(children)
    last_parent = set_loaded(last_parent, refl, children)
    Enum.reverse([last_parent|parents])
  end

  defp combine([{ parent, child }|rows], refl, last_parent, parents, children) do
    cond do
      nil?(parent) ->
        combine(rows, refl, last_parent, [nil|parents], children)
      compare(parent, last_parent, refl) ->
        combine(rows, refl, parent, parents, [child|children])
      true ->
        children = Enum.reverse(children)
        last_parent = set_loaded(last_parent, refl, children)
        parents = [last_parent|parents]
        combine([{ parent, child }|rows], refl, parent, parents, [])
    end
  end

  defp compare(record1, record2, refl) do
    pk = refl.primary_key
    apply(record1, pk, []) == apply(record2, pk, [])
  end

  defp set_loaded(record, refl, loaded) do
    if not is_record(refl, HasMany), do: loaded = Enum.first(loaded)
    field = refl.field
    association = apply(record, field, [])
    association = association.__assoc__(:loaded, loaded)
    apply(record, field, [association])
  end
end
