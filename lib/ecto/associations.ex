defmodule Ecto.Associations do
  @moduledoc """
  Utilities on associations.
  """

  alias Ecto.Query.Query
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

  def transform_result({ :assoc, _, [parent, fields] }, results, Query[] = query) do
    merge(results, parent, fields, query)
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

  ## ASSOCIATION JOIN MERGER ##

  defp merge(rows, var, fields, query) do
    refls = create_refls(var, fields, query)
    { _, _, acc } = create_acc(fields)
    acc = { HashSet.new, [], acc }

    { _keys, parents, children } = Enum.reduce(rows, acc, &merge_to_dict(&1, { nil, refls }, &2))
    parents = lc parent inlist parents, do: build_record({ 0, parent }, refls, children) |> elem(1)
    Enum.reverse(parents)
  end

  defp build_record({ pos, parent }, refls, fields) do
    zipped = Enum.zip(refls, fields)
    new_parent =
      Enum.reduce(zipped, parent, fn { refl, field }, parent ->
        { refl, refls } = refl
        { _, children, sub_children } = field

        record_key = apply(parent, record_key(refl), [])
        if record_key do
          my_children = Dict.get(children, record_key) || []
          built_children = lc child inlist my_children, do: build_record(child, refls, sub_children)
        else
          built_children = []
        end

        sorted_children = built_children
          |> Enum.sort(&compare/2)
          |> Enum.map(&elem(&1, 1))
        set_loaded(parent, refl, sorted_children)
      end)

    { pos, new_parent }
  end

  defp merge_to_dict({ record, sub_records }, { refl, sub_refls }, { keys, dict, sub_dicts }) do
    if not (nil?(record) or Set.member?(keys, record.primary_key)) do
      keys = Set.put(keys, record.primary_key)
      if refl do
        assoc_key = apply(record, assoc_key(refl), [])
        item = { Dict.size(dict), record }
        dict = Dict.update(dict, assoc_key, [item], &[item|&1])
      else
        dict = [record|dict]
      end
    end

    zipped = List.zip([sub_records, sub_refls, sub_dicts])
    sub_dicts = lc { recs, refls, dicts } inlist zipped do
      merge_to_dict(recs, refls, dicts)
    end

    { keys, dict, sub_dicts }
  end

  defp create_refls(var, fields, Query[] = query) do
    Enum.map(fields, fn { field, nested } ->
      { inner_var, fields } = Util.assoc_extract(nested)

      entity = Util.find_source(query.sources, var) |> Util.entity
      refl = entity.__entity__(:association, field)

      { refl, create_refls(inner_var, fields, query) }
    end)
  end

  defp create_acc(fields) do
    acc = Enum.map(fields, fn { _field, nested } ->
      { _, fields } = Util.assoc_extract(nested)
      create_acc(fields)
    end)
    { HashSet.new, HashDict.new, acc }
  end

  # TODO: MOVE! Preloader also uses this
  defp record_key(BelongsTo[] = refl), do: refl.foreign_key
  defp record_key(refl), do: refl.primary_key

  defp assoc_key(BelongsTo[] = refl), do: refl.primary_key
  defp assoc_key(refl), do: refl.foreign_key

  defp set_loaded(record, refl, loaded) do
    if not is_record(refl, HasMany), do: loaded = Enum.first(loaded)
    field = refl.field
    association = apply(record, field, [])
    association = association.__assoc__(:loaded, loaded)
    apply(record, field, [association])
  end

  defp compare({ pos1, _ }, { pos2, _ }), do: pos1 < pos2
end
