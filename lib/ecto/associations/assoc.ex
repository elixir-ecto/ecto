defmodule Ecto.Associations.Assoc do
  @moduledoc """
  This module provides the assoc selector merger and utilities around it.
  """

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util
  alias Ecto.Associations

  @doc """
  Transforms a result set based on the assoc selector, loading the associations
  onto their parent entity. See `Ecto.Query.select/3`.
  """
  @spec run([Record.t], Query.t) :: [Record.t]
  def run([], _query), do: []

  def run(results, Query[] = query) do
    case query.select do
      QueryExpr[expr: {:assoc, _, [parent, fields]}] ->
        merge(results, parent, fields, query)
      _ ->
        results
    end
  end

  @doc """
  Decomposes an `assoc(var, fields)` or `var` into `{var, fields}`.
  """
  @spec decompose_assoc(Macro.t) :: {Macro.t, [Macro.t]}
  def decompose_assoc({:&, _, [_]} = var), do: {var, []}
  def decompose_assoc({:assoc, _, [var, fields]}), do: {var, fields}

  defp merge(rows, var, fields, query) do
    # Pre-create rose tree of reflections and accumulator dicts in the same
    # structure as the fields tree
    refls = create_refls(var, fields, query)
    {_, _, acc} = create_acc(fields)
    acc = {HashSet.new, [], acc}

    # Populate tree of dicts of associated entities from the result set
    {_keys, parents, children} = Enum.reduce(rows, acc, &merge_to_dict(&1, {nil, refls}, &2))

    # Load associated entities onto their parents
    parents = for parent <- parents, do: build_record({0, parent}, children, refls) |> elem(1)

    Enum.reverse(parents)
  end

  defp merge_to_dict({record, sub_records}, {refl, sub_refls}, {keys, dict, sub_dicts}) do
    # We recurse down the tree of the row result, the reflections and the
    # dict accumulators

    # The set makes sure that we don't add duplicated associated entities
    if not (nil?(record) or Set.member?(keys, record.primary_key)) do
      keys = Set.put(keys, record.primary_key)
      if refl do
        # Add associated entity to dict with association key, we use to
        # put the entity on the right parent later
        # Also store position so we can sort
        assoc_key = apply(record, refl.assoc_key, [])
        item = {Dict.size(dict), record}
        dict = Dict.update(dict, assoc_key, [item], &[item|&1])
      else
        # If no reflection we are at the top-most parent
        dict = [record|dict]
      end
    end

    # Recurse down
    zipped = List.zip([sub_records, sub_refls, sub_dicts])
    sub_dicts = for {recs, refls, dicts} <- zipped do
      merge_to_dict(recs, refls, dicts)
    end

    {keys, dict, sub_dicts}
  end

  defp build_record({pos, parent}, children, refls) do
    zipped = List.zip([children, refls])

    # Load all associated children onto the parent
    new_parent =
      Enum.reduce(zipped, parent, fn {child, refl}, parent ->
        {refl, refls} = refl
        {_, children, sub_children} = child

        # Get the children associated to the parent
        record_key = apply(parent, refl.key, [])
        if record_key do
          my_children = Dict.get(children, record_key) || []
          # Recurse down and build the children
          built_children = for child <- my_children, do: build_record(child, sub_children, refls)
        else
          built_children = []
        end

        # Fix ordering that was shuffled by HashDict
        sorted_children = built_children
          |> Enum.sort(&compare/2)
          |> Enum.map(&elem(&1, 1))
        Associations.set_loaded(parent, refl, sorted_children)
      end)

    {pos, new_parent}
  end

  defp create_refls(var, fields, Query[] = query) do
    Enum.map(fields, fn {field, nested} ->
      {inner_var, fields} = decompose_assoc(nested)

      entity = Util.find_source(query.sources, var) |> Util.entity
      refl = entity.__entity__(:association, field)

      {refl, create_refls(inner_var, fields, query)}
    end)
  end

  defp create_acc(fields) do
    acc = Enum.map(fields, fn {_field, nested} ->
      {_, fields} = decompose_assoc(nested)
      create_acc(fields)
    end)
    {HashSet.new, HashDict.new, acc}
  end

  defp compare({pos1, _}, {pos2, _}), do: pos1 < pos2
end
