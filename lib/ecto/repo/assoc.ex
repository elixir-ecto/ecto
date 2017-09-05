defmodule Ecto.Repo.Assoc do
  # The module invoked by repo modules
  # for association related functionality.
  @moduledoc false

  @doc """
  Transforms a result set based on query assocs, loading
  the associations onto their parent schema.
  """
  @spec query([Ecto.Schema.t], list, tuple) :: [Ecto.Schema.t]
  def query(rows, assocs, sources)

  def query([], _assocs, _sources), do: []
  def query(rows, [], _sources), do: rows

  def query(rows, assocs, sources) do
    # Create rose tree of accumulator dicts in the same
    # structure as the fields tree
    accs = create_accs(0, assocs, sources, [])

    # Populate tree of dicts of associated entities from the result set
    {_keys, _cache, rows, sub_dicts} = Enum.reduce(rows, accs, fn row, acc ->
      merge(row, acc, 0) |> elem(0)
    end)

    # Create the reflections that will be loaded into memory.
    refls = create_refls(0, assocs, sub_dicts, sources)

    # Retrieve and load the assocs from cached dictionaries recursively
    for {item, sub_structs} <- Enum.reverse(rows) do
      [load_assocs(item, refls)|sub_structs]
    end
  end

  defp merge([struct|sub_structs], {primary_keys, cache, dict, sub_dicts}, parent_key) do
    child_key =
      if struct do
        for primary_key <- primary_keys do
          case Map.get(struct, primary_key) do
            nil -> raise Ecto.NoPrimaryKeyValueError, struct: struct
            value -> value
          end
        end
      end

    # Traverse sub_structs adding one by one to the tree.
    # Note we need to traverse even if we don't have a child_key
    # due to nested associations.
    {sub_dicts, sub_structs} =
      Enum.map_reduce sub_dicts, sub_structs, &merge(&2, &1, child_key)

    # Now if we have a struct and its parent key, we store the current
    # data unless we have already processed it.
    cache_key = {parent_key, child_key}

    if struct && parent_key && not Map.get(cache, cache_key, false) do
      cache = Map.put(cache, cache_key, true)
      item = {child_key, struct}

      # If we have a list, we are at the root,
      # so we also store the sub structs
      dict =
        if is_list(dict) do
          [{item, sub_structs}|dict]
        else
          Map.update(dict, parent_key, [item], &[item|&1])
        end

      {{primary_keys, cache, dict, sub_dicts}, sub_structs}
    else
      {{primary_keys, cache, dict, sub_dicts}, sub_structs}
    end
  end

  defp load_assocs({child_key, struct}, refls) do
    Enum.reduce refls, struct, fn {dict, refl, sub_refls}, acc ->
      %{field: field, cardinality: cardinality} = refl
      loaded =
        dict
        |> Map.get(child_key, [])
        |> Enum.reverse()
        |> Enum.map(&load_assocs(&1, sub_refls))
        |> maybe_first(cardinality)
      Map.put(acc, field, loaded)
    end
  end

  defp maybe_first(list, :one), do: List.first(list)
  defp maybe_first(list, _), do: list

  defp create_refls(idx, fields, dicts, sources) do
    {_source, schema} = elem(sources, idx)

    Enum.map(:lists.zip(dicts, fields), fn
      {{_primary_keys, _cache, dict, sub_dicts}, {field, {child_idx, child_fields}}} ->
        sub_refls = create_refls(child_idx, child_fields, sub_dicts, sources)
        {dict, schema.__schema__(:association, field), sub_refls}
    end)
  end

  defp create_accs(idx, fields, sources, initial_dict) do
    acc = Enum.map(fields, fn {_field, {child_idx, child_fields}} ->
      create_accs(child_idx, child_fields, sources, %{})
    end)

    {_source, schema} = elem(sources, idx)
    {schema.__schema__(:primary_key), %{}, initial_dict, acc}
  end
end
