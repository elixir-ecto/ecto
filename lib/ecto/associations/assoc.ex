defmodule Ecto.Associations.Assoc do
  @moduledoc """
  This module provides the assoc selector merger and utilities around it.
  """

  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util

  @doc """
  Transforms a result set based on the assoc selector, loading the associations
  onto their parent model. See `Ecto.Query.select/3`.
  """
  @spec run([Ecto.Model.t], Ecto.Query.t) :: [Ecto.Model.t]
  def run([], _query), do: []

  def run(results, query) do
    case query.select do
      %QueryExpr{expr: {:assoc, _, [parent, fields]}} ->
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
    # Pre-create rose tree of reflections and accumulator
    # dicts in the same structure as the fields tree
    refls = create_refls(var, fields, query)
    accs  = create_accs(fields)

    # Populate tree of dicts of associated entities from the result set
    {_keys, dicts, sub_dicts} = Enum.reduce(rows, accs, &merge_to_dict(&1, &2, 0))

    # Retrieve and load the assocs from cached dictionaries recursively
    load_assocs(HashDict.fetch!(dicts, 0), sub_dicts, refls)
  end

  defp load_assocs(structs, sub_dicts, refls) do
    for {child_key, struct} <- Enum.reverse(structs) do
      Enum.reduce :lists.zip(sub_dicts, refls), struct, fn
        {{_keys, dict, sub_dicts}, {refl, refls}}, acc ->
          loaded = load_assocs(HashDict.get(dict, child_key, []), sub_dicts, refls)

          # TODO: Do not hardcode
          unless refl.__struct__ == Ecto.Associations.HasMany do
            loaded = List.first(loaded)
          end

          Map.put(acc, refl.field, loaded)
      end
    end
  end

  defp merge_to_dict({struct, sub_structs}, {keys, dict, sub_dicts}, parent_key) do
    # If we have a struct, stored it in the parent key
    # unless we have already processed this particular entry.
    if struct do
      child_key = Ecto.Model.primary_key(struct) ||
                    raise Ecto.NoPrimaryKeyError, model: struct.__struct__

      cache = {parent_key, child_key}

      if parent_key && not HashSet.member?(keys, cache) do
        keys = HashSet.put(keys, cache)
        item = {child_key, struct}
        dict = HashDict.update(dict, parent_key, [item], &[item|&1])
      end
    end

    # Now recurse down the tree of results along side the accumulators
    sub_dicts = for {recs, dicts} <- :lists.zip(sub_structs, sub_dicts) do
      merge_to_dict(recs, dicts, child_key)
    end

    {keys, dict, sub_dicts}
  end

  defp create_refls(var, fields, query) do
    Enum.map(fields, fn {field, nested} ->
      {child_var, child_fields} = decompose_assoc(nested)

      {_source, model} = Util.find_source(query.sources, var)
      refl = model.__schema__(:association, field)

      {refl, create_refls(child_var, child_fields, query)}
    end)
  end

  defp create_accs(fields) do
    acc = Enum.map(fields, fn {_field, nested} ->
      {_, fields} = decompose_assoc(nested)
      create_accs(fields)
    end)

    {HashSet.new, HashDict.new, acc}
  end
end
