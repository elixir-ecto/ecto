defmodule Ecto.Associations.Assoc do
  @moduledoc """
  This module provides the assoc selector merger and utilities around it.
  """

  alias Ecto.Query.Query
  alias Ecto.Query.Util
  alias Ecto.Reflections.HasMany

  @doc """
  Transforms a result set based on the assoc selector, combining the entities
  specified in the assoc selector.  See `Ecto.Query.select/3`.
  """
  def run([], _expr, _query), do: []

  def run(results, { :assoc, _, [parent, fields] }, Query[] = query) do
    merge(results, parent, fields, query)
  end

  def run(results, _expr, _query), do: results

  @doc """
  Decomposes an `assoc(var, fields)` or `var` into `{ var, fields }`.
  """
  def decompose_assoc({ :&, _, [_] } = var), do: { var, [] }
  def decompose_assoc({ :assoc, _, [var, fields] }), do: { var, fields }

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

        record_key = apply(parent, Util.record_key(refl), [])
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
        assoc_key = apply(record, Util.assoc_key(refl), [])
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
      { inner_var, fields } = decompose_assoc(nested)

      entity = Util.find_source(query.sources, var) |> Util.entity
      refl = entity.__entity__(:association, field)

      { refl, create_refls(inner_var, fields, query) }
    end)
  end

  defp create_acc(fields) do
    acc = Enum.map(fields, fn { _field, nested } ->
      { _, fields } = decompose_assoc(nested)
      create_acc(fields)
    end)
    { HashSet.new, HashDict.new, acc }
  end

  defp set_loaded(record, refl, loaded) do
    if not is_record(refl, HasMany), do: loaded = Enum.first(loaded)
    field = refl.field
    association = apply(record, field, [])
    association = association.__assoc__(:loaded, loaded)
    apply(record, field, [association])
  end

  defp compare({ pos1, _ }, { pos2, _ }), do: pos1 < pos2
end
