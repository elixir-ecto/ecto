defmodule Ecto.Repo.Assoc do
  # The module invoked by repo modules
  # for association related functionality.
  @moduledoc false

  @doc """
  Transforms a result set based on query assocs, loading
  the associations onto their parent schema.
  """
  @spec query([list], list, tuple, (list -> list)) :: [Ecto.Schema.t]
  def query(rows, assocs, sources, fun)

  def query([], _assocs, _sources, _fun), do: []
  def query(rows, [], _sources, fun), do: Enum.map(rows, fun)

  def query(rows, assocs, sources, fun) do
    # Create rose tree of accumulator dicts in the same
    # structure as the fields tree
    accs = create_accs(0, assocs, sources, [])

    # Populate tree of dicts of associated entities from the result set
    {_keys, _cache, rows, sub_dicts} = Enum.reduce(rows, accs, fn row, acc ->
      merge(fun.(row), acc, 0) |> elem(0)
    end)

    # Create the reflections that will be loaded into memory.
    refls = create_refls(0, assocs, sub_dicts, sources)

    # Retrieve and load the assocs from cached dictionaries recursively
    for {item, sub_structs} <- Enum.reverse(rows) do
      [load_assocs(item, refls)|sub_structs]
    end
  end

  defp merge([struct|sub_structs], {primary_keys, cache, dict, sub_dicts}, parent_key) do
    {struct, child_key} =
      if struct do
        {child_key, all_nil?} =
          Enum.map_reduce(primary_keys, true, fn primary_key, all_nil? ->
            case struct do
              %_{^primary_key => nil} -> raise Ecto.NoPrimaryKeyValueError, struct: struct
              # We allow maps to be returned with all `nil` values in queries without
              # preloads. For preloads we have to treat maps with all `nil` values as
              # `nil` instead of a map otherwise we can't associate the missing
              # association to the parent struct
              %{^primary_key => value} -> {value, all_nil? and value == nil}
              %{} -> raise Ecto.NoPrimaryKeyValueError, struct: struct
            end
          end)

        if all_nil?, do: {nil, nil}, else: {struct, child_key}
      else
        {nil, nil}
      end

    # Traverse sub_structs adding one by one to the tree.
    # Note we need to traverse even if we don't have a child_key
    # due to nested associations.
    {sub_dicts, sub_structs} = Enum.map_reduce(sub_dicts, sub_structs, &merge(&2, &1, child_key))

    cache_key = cache_key(parent_key, child_key, sub_structs, dict)

    if struct && parent_key && not Map.get(cache, cache_key, false) do
      cache = Map.put(cache, cache_key, true)
      item = {child_key, struct}

      # If we have a list, we are at the root, so we also store the sub structs
      dict = update_dict(dict, parent_key, item, sub_structs)

      {{primary_keys, cache, dict, sub_dicts}, sub_structs}
    else
      {{primary_keys, cache, dict, sub_dicts}, sub_structs}
    end
  end

  defp cache_key(parent_key, child_key, sub_structs, dict) when is_list(dict) do
    {parent_key, child_key, sub_structs}
  end

  defp cache_key(parent_key, child_key, _sub_structs, dict) when is_map(dict) do
    {parent_key, child_key}
  end

  defp update_dict(dict, _parent_key, item, sub_structs) when is_list(dict) do
    [{item, sub_structs} | dict]
  end

  defp update_dict(dict, parent_key, item, _sub_structs) when is_map(dict) do
    Map.update(dict, parent_key, [item], &[item | &1])
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
    schema = get_assoc_schema(sources, idx)

    Enum.map(:lists.zip(dicts, fields), fn
      {{_primary_keys, _cache, dict, sub_dicts}, {field, {child_idx, child_fields}}} ->
        refl = schema.__schema__(:association, field)
        sub_refls = create_refls(child_idx, child_fields, sub_dicts, sources)
        {dict, refl, sub_refls}
    end)
  end

  defp create_accs(idx, fields, sources, initial_dict) do
    acc = Enum.map(fields, fn {_field, {child_idx, child_fields}} ->
      create_accs(child_idx, child_fields, sources, %{})
    end)

    schema = get_assoc_schema(sources, idx)

    case schema.__schema__(:primary_key) do
      [] -> raise Ecto.NoPrimaryKeyFieldError, schema: schema
      pk -> {pk, %{}, initial_dict, acc}
    end
  end

  defp get_assoc_schema(sources, idx) do
    case elem(sources, idx) do
      {_, schema, _} ->
        schema

      %Ecto.SubQuery{select: {:source, {_, schema}, _, _}} ->
        schema
    end
  end
end
