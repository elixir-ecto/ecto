defmodule Ecto.Associations do
  @moduledoc """
  Utilities on associations.
  """

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.AssocJoinExpr
  alias Ecto.Query.Util
  alias Ecto.Reflections.HasOne
  alias Ecto.Reflections.HasMany
  alias Ecto.Reflections.BelongsTo

  @doc """
  Returns true if join expression is an assocation join.
  """
  def assoc_join?({ :., _, _ }), do: true
  def assoc_join?({ :{}, _, [:., _, _] }), do: true
  def assoc_join?(_), do: false

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
    entity = query.from.__model__(:entity)
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
    pk = refl.primary_key
    ids = Enum.filter_map(records, &(&1), &apply(&1, pk, []))

    where_expr = quote do &0.unquote(refl.foreign_key) in unquote(ids) end
    where = QueryExpr[expr: where_expr]
    order_bys = QueryExpr[expr: [ { nil, quote do &0 end, refl.foreign_key } ]]
    Query[from: refl.associated, wheres: [where], order_bys: [order_bys]]
  end

  def preload_query(BelongsTo[] = refl, records) do
    fun = &(apply(&1, refl.foreign_key, []))
    ids = Enum.filter_map(records, fun, fun)
    pk = refl.primary_key

    where_expr = quote do &0.unquote(pk) in unquote(ids) end
    where = QueryExpr[expr: where_expr]
    order_bys = QueryExpr[expr: [ { nil, quote do &0 end, pk } ]]
    Query[from: refl.associated, wheres: [where], order_bys: [order_bys]]
  end

  defp combine([], refl, last_parent, parents, children) do
    children = Enum.reverse(children)
    last_parent = set_loaded(last_parent, refl, children)
    Enum.reverse([last_parent|parents])
  end

  defp combine([{ parent, child }|rows], refl, last_parent, parents, children) do
    pk = refl.primary_key
    cond do
      nil?(parent) ->
        combine(rows, refl, last_parent, [nil|parents], children)
      apply(parent, pk, []) == apply(last_parent, pk, []) ->
        combine(rows, refl, parent, parents, [child|children])
      true ->
        children = Enum.reverse(children)
        last_parent = set_loaded(last_parent, refl, children)
        parents = [last_parent|parents]
        combine([{ parent, child }|rows], refl, parent, parents, [])
    end
  end

  defp set_loaded(record, field, loaded) when is_atom(field) do
    association = apply(record, field, [])
    association = association.__assoc__(:loaded, loaded)
    apply(record, field, [association])
  end

  defp set_loaded(record, HasMany[field: field], loaded) do
    set_loaded(record, field, loaded)
  end

  defp set_loaded(record, refl, loaded) do
    loaded = Enum.first(loaded)
    set_loaded(record, refl.field, loaded)
  end
end
