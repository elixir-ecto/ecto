defmodule Ecto.Repo.Preloader do
  # The module invoked by user defined repo_names
  # for preload related functionality.
  @moduledoc false

  require Ecto.Query
  require Logger

  @doc """
  Transforms a result set based on query preloads, loading
  the associations onto their parent schema.
  """
  @spec query([list], Ecto.Repo.t, list, Access.t, fun, {adapter_meta :: map, opts :: Keyword.t}) :: [list]
  def query([], _repo_name, _preloads, _take, _fun, _tuplet), do: []
  def query(rows, _repo_name, [], _take, fun, _tuplet), do: Enum.map(rows, fun)

  def query(rows, repo_name, preloads, take, fun, tuplet) do
    rows
    |> extract()
    |> normalize_and_preload_each(repo_name, preloads, take, tuplet)
    |> unextract(rows, fun)
  end

  defp extract([[nil|_]|t2]), do: extract(t2)
  defp extract([[h|_]|t2]), do: [h|extract(t2)]
  defp extract([]), do: []

  defp unextract(structs, [[nil|_] = h2|t2], fun), do: [fun.(h2)|unextract(structs, t2, fun)]
  defp unextract([h1|structs], [[_|t1]|t2], fun), do: [fun.([h1|t1])|unextract(structs, t2, fun)]
  defp unextract([], [], _fun), do: []

  @doc """
  Implementation for `Ecto.Repo.preload/2`.
  """
  @spec preload(structs, atom, atom | list, {adapter_meta :: map, opts :: Keyword.t}) ::
                structs when structs: [Ecto.Schema.t] | Ecto.Schema.t | nil
  def preload(nil, _repo_name, _preloads, _tuplet) do
    nil
  end

  def preload(structs, repo_name, preloads, {_adapter_meta, opts} = tuplet) when is_list(structs) do
    normalize_and_preload_each(structs, repo_name, preloads, opts[:take], tuplet)
  end

  def preload(struct, repo_name, preloads, {_adapter_meta, opts} = tuplet) when is_map(struct) do
    normalize_and_preload_each([struct], repo_name, preloads, opts[:take], tuplet) |> hd()
  end

  defp normalize_and_preload_each(structs, repo_name, preloads, take, tuplet) do
    preloads = normalize(preloads, take, preloads)
    preload_each(structs, repo_name, preloads, tuplet)
  rescue
    e ->
      # Reraise errors so we ignore the preload inner stacktrace
      filter_and_reraise e, __STACKTRACE__
  end

  ## Preloading

  defp preload_each(structs, _repo_name, [], _tuplet),   do: structs
  defp preload_each([], _repo_name, _preloads, _tuplet), do: []
  defp preload_each(structs, repo_name, preloads, tuplet) do
    if sample = Enum.find(structs, & &1) do
      module = sample.__struct__
      prefix = preload_prefix(tuplet, sample)
      {assocs, throughs, embeds} = expand(module, preloads, {%{}, %{}, []})
      structs = preload_embeds(structs, embeds, repo_name, tuplet)

      {fetched_assocs, to_fetch_queries} =
        prepare_queries(structs, module, assocs, prefix, repo_name, tuplet)

      fetched_queries = maybe_pmap(to_fetch_queries, repo_name, tuplet)
      assocs = preload_assocs(fetched_assocs, fetched_queries, repo_name, tuplet)
      throughs = Map.values(throughs)

      for struct <- structs do
        struct = Enum.reduce assocs, struct, &load_assoc/2
        struct = Enum.reduce throughs, struct, &load_through/2
        struct
      end
    else
      structs
    end
  end

  defp preload_prefix({_adapter_meta, opts}, sample) do
    case Keyword.fetch(opts, :prefix) do
      {:ok, prefix} ->
        prefix

      :error ->
        case sample do
          %{__meta__: %{prefix: prefix}} -> prefix
          # Must be an embedded schema
          _ -> nil
        end
    end
  end

  ## Association preloading

  # First we traverse all assocs and find which queries we need to run.
  defp prepare_queries(structs, module, assocs, prefix, repo_name, tuplet) do
    Enum.reduce(assocs, {[], []}, fn
      {_key, {{:assoc, assoc, related_key}, take, query, preloads}}, {assocs, queries} ->
        {fetch_ids, loaded_ids, loaded_structs} = fetch_ids(structs, module, assoc, tuplet)

        queries =
          if fetch_ids != [] do
            [
              fn tuplet ->
                fetch_query(fetch_ids, assoc, repo_name, query, prefix, related_key, take, tuplet)
              end
              | queries
            ]
          else
            queries
          end

        {[{assoc, fetch_ids != [], loaded_ids, loaded_structs, preloads} | assocs], queries}
    end)
  end

  # Then we execute queries in parallel
  defp maybe_pmap(preloaders, _repo_name, {adapter_meta, opts}) do
    if match?([_,_|_], preloaders) and not adapter_meta.adapter.checked_out?(adapter_meta) and
         Keyword.get(opts, :in_parallel, true) do
      # We pass caller: self() so the ownership pool knows where
      # to fetch the connection from and set the proper timeouts.
      # Note while the ownership pool uses '$callers' from pdict,
      # it does not do so in automatic mode, hence this line is
      # still necessary.
      opts = Keyword.put_new(opts, :caller, self())

      preloaders
      |> Task.async_stream(&(&1.({adapter_meta, opts})), timeout: :infinity)
      |> Enum.map(fn {:ok, assoc} -> assoc end)
    else
      Enum.map(preloaders, &(&1.({adapter_meta, opts})))
    end
  end

  # Then we unpack the query results, merge them, and preload recursively
  defp preload_assocs(
         [{assoc, query?, loaded_ids, loaded_structs, preloads} | assocs],
         queries,
         repo_name,
         tuplet
       ) do
    {fetch_ids, fetch_structs, queries} = maybe_unpack_query(query?, queries)
    all = preload_each(Enum.reverse(loaded_structs, fetch_structs), repo_name, preloads, tuplet)
    entry = {:assoc, assoc, assoc_map(assoc.cardinality, Enum.reverse(loaded_ids, fetch_ids), all)}
    [entry | preload_assocs(assocs, queries, repo_name, tuplet)]
  end

  defp preload_assocs([], [], _repo_name, _tuplet), do: []

  defp preload_embeds(structs, [], _repo_name, _tuplet), do: structs

  defp preload_embeds(structs, [embed | embeds], repo_name, tuplet) do

    {%{field: field, cardinality: card}, sub_preloads} = embed

    {embed_structs, counts} =
      Enum.flat_map_reduce(structs, [], fn
        %{^field => embeds}, counts when is_list(embeds) -> {embeds, [length(embeds) | counts]}
        %{^field => nil}, counts -> {[], [0 | counts]}
        %{^field => embed}, counts -> {[embed], [1 | counts]}
        nil, counts -> {[], [0 | counts]}
        struct, _counts -> raise ArgumentError, "expected #{inspect(struct)} to contain embed `#{field}`"
      end)

    embed_structs = preload_each(embed_structs, repo_name, sub_preloads, tuplet)
    structs = load_embeds(card, field, structs, embed_structs, Enum.reverse(counts), [])
    preload_embeds(structs, embeds, repo_name, tuplet)
  end

  defp load_embeds(_card, _field, [], [], [], acc), do: Enum.reverse(acc)

  defp load_embeds(card, field, [struct | structs], embed_structs, [0 | counts], acc),
    do: load_embeds(card, field, structs, embed_structs, counts, [struct | acc])

  defp load_embeds(:one, field, [struct | structs], [embed_struct | embed_structs], [1 | counts], acc),
    do: load_embeds(:one, field, structs, embed_structs, counts, [Map.put(struct, field, embed_struct) | acc])

  defp load_embeds(:many, field, [struct | structs], embed_structs, [count | counts], acc) do
    {current_embeds, rest_embeds} = split_n(embed_structs, count, [])
    acc = [Map.put(struct, field, Enum.reverse(current_embeds)) | acc]
    load_embeds(:many, field, structs, rest_embeds, counts, acc)
  end

  defp maybe_unpack_query(false, queries), do: {[], [], queries}
  defp maybe_unpack_query(true, [{ids, structs} | queries]), do: {ids, structs, queries}

  defp fetch_ids(structs, module, assoc, {_adapter_meta, opts}) do
    %{field: field, owner_key: owner_key, cardinality: card} = assoc
    force? = Keyword.get(opts, :force, false)

    Enum.reduce structs, {[], [], []}, fn
      nil, acc ->
        acc
      struct, {fetch_ids, loaded_ids, loaded_structs} ->
        assert_struct!(module, struct)
        %{^owner_key => id, ^field => value} = struct
        loaded? = Ecto.assoc_loaded?(value) and not force?

        if loaded? and is_nil(id) and not Ecto.Changeset.Relation.empty?(assoc, value) do
          Logger.warn """
          association `#{field}` for `#{inspect(module)}` has a loaded value but \
          its association key `#{owner_key}` is nil. This usually means one of:

            * `#{owner_key}` was not selected in a query
            * the struct was set with default values for `#{field}` which now you want to override

          If this is intentional, set force: true to disable this warning
          """
        end

        cond do
          card == :one and loaded? ->
            {fetch_ids, [id | loaded_ids], [value | loaded_structs]}
          card == :many and loaded? ->
            {fetch_ids, [{id, length(value)} | loaded_ids], value ++ loaded_structs}
          is_nil(id) ->
            {fetch_ids, loaded_ids, loaded_structs}
          true ->
            {[id | fetch_ids], loaded_ids, loaded_structs}
        end
    end
  end

  defp fetch_query(ids, assoc, _repo_name, query, _prefix, related_key, _take, _tuplet) when is_function(query, 1) do
    # Note we use an explicit sort because we don't want
    # to reorder based on the struct. Only the ID.
    ids
    |> Enum.uniq
    |> query.()
    |> fetched_records_to_tuple_ids(assoc, related_key)
    |> Enum.sort(fn {id1, _}, {id2, _} -> id1 <= id2 end)
    |> unzip_ids([], [])
  end

  defp fetch_query(ids, %{cardinality: card} = assoc, repo_name, query, prefix, related_key, take, tuplet) do
    query = assoc.__struct__.assoc_query(assoc, query, Enum.uniq(ids))
    field = related_key_to_field(query, related_key)

    # Normalize query
    query = %{Ecto.Query.Planner.ensure_select(query, take || true) | prefix: prefix}

    # Add the related key to the query results
    query = update_in query.select.expr, &{:{}, [], [field, &1]}

    # If we are returning many results, we must sort by the key too
    query =
      case {card, query.combinations} do
        {:many, [{kind, _} | []]} ->
          raise ArgumentError,
                "`#{kind}` queries must be wrapped inside of a subquery " <>
                  "when preloading a `has_many` or `many_to_many` association. " <>
                  "You must also ensure that all members of the `#{kind}` query " <>
                  "select the parent's foreign key"

        {:many, _} ->
          update_in query.order_bys, fn order_bys ->
            [%Ecto.Query.QueryExpr{expr: preload_order(assoc, query, field), params: [],
                                   file: __ENV__.file, line: __ENV__.line}|order_bys]
          end
        {:one, _} ->
          query
      end

    unzip_ids Ecto.Repo.Queryable.all(repo_name, query, tuplet), [], []
  end

  defp fetched_records_to_tuple_ids([], _assoc, _related_key),
    do: []

  defp fetched_records_to_tuple_ids([%{} | _] = entries, _assoc, {0, key}),
    do: Enum.map(entries, &{Map.fetch!(&1, key), &1})

  defp fetched_records_to_tuple_ids([{_, %{}} | _] = entries, _assoc, _related_key),
    do: entries

  defp fetched_records_to_tuple_ids([entry | _], assoc, _),
    do: raise """
    invalid custom preload for `#{assoc.field}` on `#{inspect assoc.owner}`.

    For many_to_many associations, the custom function given to preload should \
    return a tuple with the associated key as first element and the record as \
    second element.

    For example, imagine posts has many to many tags through a posts_tags table. \
    When preloading the tags, you may write:

        custom_tags = fn post_ids ->
          Repo.all(
            from t in Tag,
                 join: pt in "posts_tags",
                 where: t.custom and pt.post_id in ^post_ids and pt.tag_id == t.id
          )
        end

        from Post, preload: [tags: ^custom_tags]

    Unfortunately the query above is not enough because Ecto won't know how to \
    associate the posts with the tags. In those cases, you need to return a tuple \
    with the `post_id` as first element and the tag record as second. The new query \
    will have a select field as follows:

        from t in Tag,
             join: pt in "posts_tags",
             where: t.custom and pt.post_id in ^post_ids and pt.tag_id == t.id,
             select: {pt.post_id, t}

    We expected a tuple but we got: #{inspect(entry)}
    """

  defp preload_order(assoc, query, related_field) do
    custom_order_by = Enum.map(assoc.preload_order, fn
      {direction, field} ->
        {direction, related_key_to_field(query, {0, field})}
      field ->
        {:asc, related_key_to_field(query, {0, field})}
    end)

    [{:asc, related_field} | custom_order_by]
  end

  defp related_key_to_field(query, {pos, key, field_type}) do
    field_ast = related_key_to_field(query, {pos, key})

    {:type, [], [field_ast, field_type]}
  end

  defp related_key_to_field(query, {pos, key}) do
    {{:., [], [{:&, [], [related_key_pos(query, pos)]}, key]}, [], []}
  end

  defp related_key_pos(_query, pos) when pos >= 0, do: pos
  defp related_key_pos(query, pos), do: Ecto.Query.Builder.count_binds(query) + pos

  defp unzip_ids([{k, v}|t], acc1, acc2), do: unzip_ids(t, [k|acc1], [v|acc2])
  defp unzip_ids([], acc1, acc2), do: {acc1, acc2}

  defp assert_struct!(mod, %{__struct__: mod}), do: true
  defp assert_struct!(mod, %{__struct__: struct}) do
    raise ArgumentError, "expected a homogeneous list containing the same struct, " <>
                         "got: #{inspect mod} and #{inspect struct}"
  end

  defp assoc_map(:one, ids, structs) do
    one_assoc_map(ids, structs, %{})
  end
  defp assoc_map(:many, ids, structs) do
    many_assoc_map(ids, structs, %{})
  end

  defp one_assoc_map([id|ids], [struct|structs], map) do
    one_assoc_map(ids, structs, Map.put(map, id, struct))
  end
  defp one_assoc_map([], [], map) do
    map
  end

  defp many_assoc_map([{id, n}|ids], structs, map) do
    {acc, structs} = split_n(structs, n, [])
    many_assoc_map(ids, structs, Map.put(map, id, acc))
  end
  defp many_assoc_map([id|ids], [struct|structs], map) do
    {ids, structs, acc} = split_while(ids, structs, id, [struct])
    many_assoc_map(ids, structs, Map.put(map, id, acc))
  end
  defp many_assoc_map([], [], map) do
    map
  end

  defp split_n(structs, 0, acc), do: {acc, structs}
  defp split_n([struct | structs], n, acc), do: split_n(structs, n - 1, [struct | acc])

  defp split_while([id|ids], [struct|structs], id, acc),
    do: split_while(ids, structs, id, [struct|acc])
  defp split_while(ids, structs, _id, acc),
    do: {ids, structs, acc}

  ## Load preloaded data

  defp load_assoc({:assoc, _assoc, _ids}, nil) do
    nil
  end

  defp load_assoc({:assoc, assoc, ids}, struct) do
    %{field: field, owner_key: owner_key, cardinality: cardinality} = assoc
    key = Map.fetch!(struct, owner_key)

    loaded =
      case ids do
        %{^key => value} -> value
        _ when cardinality == :many -> []
        _ -> nil
      end

    Map.put(struct, field, loaded)
  end

  defp load_through({:through, _assoc, _throughs}, nil) do
    nil
  end

  defp load_through({:through, assoc, throughs}, struct) do
    %{cardinality: cardinality, field: field, owner: owner} = assoc
    {loaded, _} = Enum.reduce(throughs, {[struct], owner}, &recur_through/2)
    Map.put(struct, field, maybe_first(loaded, cardinality))
  end

  defp maybe_first(list, :one), do: List.first(list)
  defp maybe_first(list, _), do: list

  defp recur_through(field, {structs, owner}) do
    assoc = owner.__schema__(:association, field)
    case assoc.__struct__.preload_info(assoc) do
      {:assoc, %{related: related}, _} ->
        pk_fields =
          related.__schema__(:primary_key)
          |> validate_has_pk_field!(related, assoc)

        {children, _} =
          Enum.reduce(structs, {[], %{}}, fn struct, acc ->
            struct
            |> Map.fetch!(field)
            |> List.wrap()
            |> Enum.reduce(acc, fn child, {fresh, set} ->
              pk_values =
                child
                |> through_pks(pk_fields, assoc)
                |> validate_non_null_pk!(child, pk_fields, assoc)

              case set do
                %{^pk_values => true} ->
                  {fresh, set}
                _ ->
                  {[child|fresh], Map.put(set, pk_values, true)}
              end
            end)
          end)

        {Enum.reverse(children), related}

      {:through, _, through} ->
        Enum.reduce(through, {structs, owner}, &recur_through/2)
    end
  end

  defp validate_has_pk_field!([], related, assoc) do
    raise ArgumentError,
          "cannot preload through association `#{assoc.field}` on " <>
            "`#{inspect assoc.owner}`. Ecto expected the #{inspect related} schema " <>
            "to have at least one primary key field"
  end

  defp validate_has_pk_field!(pk_fields, _related, _assoc), do: pk_fields

  defp through_pks(map, pks, assoc) do
    Enum.map(pks, fn pk ->
      case map do
        %{^pk => value} ->
          value

        _ ->
          raise ArgumentError,
               "cannot preload through association `#{assoc.field}` on " <>
                 "`#{inspect assoc.owner}`. Ecto expected a map/struct with " <>
                 "the key `#{pk}` but got: #{inspect map}"
      end
    end)
  end

  defp validate_non_null_pk!(values, map, pks, assoc) do
    case values do
      [nil | _] ->
        raise ArgumentError,
              "cannot preload through association `#{assoc.field}` on " <>
                "`#{inspect assoc.owner}` because the primary key `#{hd(pks)}` " <>
                "is nil for map/struct: #{inspect map}"

      _ ->
        values
    end
  end

  ## Normalizer

  def normalize(preload, take, original) do
    normalize_each(wrap(preload, original), [], take, original)
  end

  defp normalize_each({atom, {query, list}}, acc, take, original)
       when is_atom(atom) and (is_map(query) or is_function(query, 1)) do
    fields = take(take, atom)
    [{atom, {fields, query!(query), normalize_each(wrap(list, original), [], fields, original)}}|acc]
  end

  defp normalize_each({atom, query}, acc, take, _original)
       when is_atom(atom) and (is_map(query) or is_function(query, 1)) do
    [{atom, {take(take, atom), query!(query), []}}|acc]
  end

  defp normalize_each({atom, list}, acc, take, original) when is_atom(atom) do
    fields = take(take, atom)
    [{atom, {fields, nil, normalize_each(wrap(list, original), [], fields, original)}}|acc]
  end

  defp normalize_each(atom, acc, take, _original) when is_atom(atom) do
    [{atom, {take(take, atom), nil, []}}|acc]
  end

  defp normalize_each(other, acc, take, original) do
    Enum.reduce(wrap(other, original), acc, &normalize_each(&1, &2, take, original))
  end

  defp query!(query) when is_function(query, 1), do: query
  defp query!(%Ecto.Query{} = query), do: query

  defp take(take, field) do
    case Access.fetch(take, field) do
      {:ok, fields} -> List.wrap(fields)
      :error -> nil
    end
  end

  defp wrap(list, _original) when is_list(list),
    do: list
  defp wrap(atom, _original) when is_atom(atom),
    do: atom
  defp wrap(other, original) do
    raise ArgumentError, "invalid preload `#{inspect other}` in `#{inspect original}`. " <>
                         "preload expects an atom, a (nested) keyword or a (nested) list of atoms"
  end

  ## Expand

  def expand(schema, preloads, acc) do
    Enum.reduce(preloads, acc, fn {preload, {fields, query, sub_preloads}},
                                  {assocs, throughs, embeds} ->
      assoc_or_embed = association_or_embed!(schema, preload)

      info = assoc_or_embed.__struct__.preload_info(assoc_or_embed)

      case info do
        {:assoc, _, _} ->
          value = {info, fields, query, sub_preloads}
          assocs = Map.update(assocs, preload, value, &merge_preloads(preload, value, &1))
          {assocs, throughs, embeds}

        {:through, _, through} ->
          through =
            through
            |> Enum.reverse()
            |> Enum.reduce({fields, query, sub_preloads}, &{nil, nil, [{&1, &2}]})
            |> elem(2)

          expand(schema, through, {assocs, Map.put(throughs, preload, info), embeds})

        :embed ->
          if sub_preloads == [] do
            raise ArgumentError,
                  "cannot preload embedded field #{inspect(assoc_or_embed.field)} " <>
                    "without also preloading one of its associations as it has no effect"
          end

          embeds = [{assoc_or_embed, sub_preloads} | embeds]
          {assocs, throughs, embeds}
      end
    end)
  end

  defp merge_preloads(_preload, {info, _, nil, left}, {info, take, query, right}),
    do: {info, take, query, left ++ right}
  defp merge_preloads(_preload, {info, take, query, left}, {info, _, nil, right}),
    do: {info, take, query, left ++ right}
  defp merge_preloads(preload, {info, _, left, _}, {info, _, right, _}) do
    raise ArgumentError, "cannot preload `#{preload}` as it has been supplied more than once " <>
                         "with different queries: #{inspect left} and #{inspect right}"
  end

  defp association_or_embed!(schema, preload) do
    schema.__schema__(:association, preload) || schema.__schema__(:embed, preload) ||
      raise ArgumentError, "schema #{inspect schema} does not have association or embed #{inspect preload}#{maybe_module(preload)}"
  end

  defp maybe_module(assoc) do
    case Atom.to_string(assoc) do
      "Elixir." <> _ ->
        " (if you were trying to pass a schema as a query to preload, " <>
          "you have to explicitly convert it to a query by doing `from x in #{inspect assoc}` " <>
          "or by calling Ecto.Queryable.to_query/1)"

      _ ->
        ""
    end
  end

  defp filter_and_reraise(exception, stacktrace) do
    reraise exception, Enum.reject(stacktrace, &match?({__MODULE__, _, _, _}, &1))
  end
end
