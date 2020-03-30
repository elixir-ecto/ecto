defmodule Ecto.Repo.Schema do
  # The module invoked by user defined repos
  # for schema related functionality.
  @moduledoc false

  alias Ecto.Changeset
  alias Ecto.Changeset.Relation
  require Ecto.Query

  @doc """
  Implementation for `Ecto.Repo.insert_all/3`.
  """
  def insert_all(_repo, name, schema, rows, opts) when is_atom(schema) do
    do_insert_all(name, schema, schema.__schema__(:prefix),
                  schema.__schema__(:source), rows, opts)
  end

  def insert_all(_repo, name, table, rows, opts) when is_binary(table) do
    do_insert_all(name, nil, nil, table, rows, opts)
  end

  def insert_all(_repo, name, {source, schema}, rows, opts) when is_atom(schema) do
    do_insert_all(name, schema, schema.__schema__(:prefix), source, rows, opts)
  end

  defp do_insert_all(_name, _schema, _prefix, _source, [], opts) do
    if opts[:returning] do
      {0, []}
    else
      {0, nil}
    end
  end

  defp do_insert_all(name, schema, prefix, source, rows, opts) when is_list(rows) do
    {adapter, adapter_meta} = Ecto.Repo.Registry.lookup(name)
    autogen_id = schema && schema.__schema__(:autogenerate_id)
    dumper = schema && schema.__schema__(:dump)

    {return_fields_or_types, return_sources} =
      schema
      |> returning(opts)
      |> fields_to_sources(dumper)

    {rows, header} = extract_header_and_fields(rows, schema, dumper, autogen_id, adapter)
    counter = fn -> Enum.reduce(rows, 0, &length(&1) + &2) end
    schema_meta = metadata(schema, prefix, source, autogen_id, nil, opts)

    on_conflict = Keyword.get(opts, :on_conflict, :raise)
    conflict_target = Keyword.get(opts, :conflict_target, [])
    conflict_target = conflict_target(conflict_target, dumper)
    on_conflict = on_conflict(on_conflict, conflict_target, schema_meta, counter, adapter)

    {count, rows} =
      adapter.insert_all(adapter_meta, schema_meta, Map.keys(header), rows, on_conflict, return_sources, opts)

    {count, postprocess(rows, return_fields_or_types, adapter, schema, schema_meta)}
  end

  defp postprocess(nil, [], _adapter, _schema, _schema_meta) do
    nil
  end

  defp postprocess(rows, fields, _adapter, nil, _schema_meta) do
    for row <- rows, do: Map.new(Enum.zip(fields, row))
  end

  defp postprocess(rows, types, adapter, schema, %{prefix: prefix, source: source}) do
    struct = Ecto.Schema.Loader.load_struct(schema, prefix, source)

    for row <- rows do
      {loaded, _} = Ecto.Repo.Queryable.struct_load!(types, row, [], false, struct, adapter)
      loaded
    end
  end

  defp extract_header_and_fields(rows, schema, dumper, autogen_id, adapter) do
    mapper = init_mapper(schema, dumper, adapter)

    {rows, {header, has_query?}} =
      Enum.map_reduce(rows, {%{}, false}, fn fields, acc ->
        {fields, {header, has_query?}} = Enum.map_reduce(fields, acc, mapper)
        {fields, header} = autogenerate_id(autogen_id, fields, header, adapter)
        {fields, {header, has_query?}}
      end)

    if has_query? do
      rows = plan_query_in_rows(rows, header, adapter)
      {rows, header}
    else
      {rows, header}
    end
  end

  defp init_mapper(nil, _dumper, _adapter) do
    fn {field, _} = tuple, {header, has_query?} ->
      {tuple, {Map.put(header, field, true), has_query?}}
    end
  end

  defp init_mapper(schema, dumper, adapter) do
    fn {field, value}, {header, has_query?} ->
        case dumper do
          %{^field => {source, type}} ->
            case value do
              %Ecto.Query{} = query ->
                {{source, query}, {Map.put(header, source, true), true}}

              value ->
                value = dump_field!(:insert_all, schema, field, type, value, adapter)
                {{source, value}, {Map.put(header, source, true), has_query?}}
            end
          %{} ->
            raise ArgumentError, "unknown field `#{inspect(field)}` in schema #{inspect(schema)} given to " <>
                                 "insert_all. Note virtual fields and associations are not supported"
        end
    end
  end

  defp plan_query_in_rows(rows, header, adapter) do
    {rows, _counter} =
      Enum.map_reduce(rows, 0, fn fields, counter ->
        Enum.flat_map_reduce(header, counter, fn {key, _}, counter ->
          case :lists.keyfind(key, 1, fields) do
            {^key, %Ecto.Query{} = query} ->
              {query, params, _} = Ecto.Query.Planner.plan(query, :all, adapter)
              {query, _} = Ecto.Query.Planner.normalize(query, :all, adapter, counter)

              {[{key, {query, params}}], counter + length(params)}

            {^key, value} ->
              {[{key, value}], counter + 1}

            false ->
              {[], counter}
          end
        end)
      end)

    rows
  end

  defp autogenerate_id(nil, fields, header, _adapter) do
    {fields, header}
  end

  defp autogenerate_id({key, source, type}, fields, header, adapter) do
    case :lists.keyfind(key, 1, fields) do
      {^key, _} ->
        {fields, header}

      false ->
        if value = Ecto.Type.adapter_autogenerate(adapter, type) do
          {[{source, value} | fields], Map.put(header, source, true)}
        else
          {fields, header}
        end
    end
  end

  @doc """
  Implementation for `Ecto.Repo.insert!/2`.
  """
  def insert!(repo, name, struct_or_changeset, opts) do
    case insert(repo, name, struct_or_changeset, opts) do
      {:ok, struct} ->
        struct

      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
    end
  end

  @doc """
  Implementation for `Ecto.Repo.update!/2`.
  """
  def update!(repo, name, struct_or_changeset, opts) do
    case update(repo, name, struct_or_changeset, opts) do
      {:ok, struct} ->
        struct

      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :update, changeset: changeset
    end
  end

  @doc """
  Implementation for `Ecto.Repo.delete!/2`.
  """
  def delete!(repo, name, struct_or_changeset, opts) do
    case delete(repo, name, struct_or_changeset, opts) do
      {:ok, struct} ->
        struct

      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :delete, changeset: changeset
    end
  end

  @doc """
  Implementation for `Ecto.Repo.insert/2`.
  """
  def insert(repo, name, %Changeset{} = changeset, opts) when is_list(opts) do
    do_insert(repo, name, changeset, opts)
  end

  def insert(repo, name, %{__struct__: _} = struct, opts) when is_list(opts) do
    do_insert(repo, name, Ecto.Changeset.change(struct), opts)
  end

  defp do_insert(repo, name, %Changeset{valid?: true} = changeset, opts) do
    {adapter, adapter_meta} = Ecto.Repo.Registry.lookup(name)
    %{prepare: prepare, repo_opts: repo_opts} = changeset
    opts = Keyword.merge(repo_opts, opts)

    struct = struct_from_changeset!(:insert, changeset)
    schema = struct.__struct__
    dumper = schema.__schema__(:dump)
    fields = schema.__schema__(:fields)
    assocs = schema.__schema__(:associations)
    embeds = schema.__schema__(:embeds)

    {return_types, return_sources} =
      schema
      |> returning(opts)
      |> add_read_after_writes(schema)
      |> fields_to_sources(dumper)

    on_conflict = Keyword.get(opts, :on_conflict, :raise)
    conflict_target = Keyword.get(opts, :conflict_target, [])
    conflict_target = conflict_target(conflict_target, dumper)

    # On insert, we always merge the whole struct into the
    # changeset as changes, except the primary key if it is nil.
    changeset = put_repo_and_action(changeset, :insert, repo, opts)
    changeset = surface_changes(changeset, struct, fields ++ assocs)

    wrap_in_transaction(adapter, adapter_meta, opts, changeset, assocs, embeds, prepare, fn ->
      assoc_opts = assoc_opts(assocs, opts)
      user_changeset = run_prepare(changeset, prepare)

      {changeset, parents, children} = pop_assocs(user_changeset, assocs)
      changeset = process_parents(changeset, parents, adapter, assoc_opts)
      changeset = repo_changes(changeset)

      if changeset.valid? do
        embeds = Ecto.Embedded.prepare(changeset, embeds, adapter, :insert)

        autogen_id = schema.__schema__(:autogenerate_id)
        schema_meta = metadata(struct, autogen_id, opts)
        changes = Map.merge(changeset.changes, embeds)

        {changes, extra, return_types, return_sources} =
          autogenerate_id(autogen_id, changes, return_types, return_sources, adapter)

        {changes, autogen} =
          dump_changes!(:insert, Map.take(changes, fields), schema, extra, dumper, adapter)

        on_conflict =
          on_conflict(on_conflict, conflict_target, schema_meta, fn -> length(changes) end, adapter)

        args = [adapter_meta, schema_meta, changes, on_conflict, return_sources, opts]

        case apply(user_changeset, adapter, :insert, args) do
          {:ok, values} ->
            values = extra ++ values

            changeset
            |> load_changes(:loaded, return_types, values, embeds, autogen, adapter, schema_meta)
            |> process_children(children, user_changeset, adapter, assoc_opts)

          {:error, _} = error ->
            error
        end
      else
        {:error, changeset}
      end
    end)
  end

  defp do_insert(repo, _name, %Changeset{valid?: false} = changeset, opts) do
    {:error, put_repo_and_action(changeset, :insert, repo, opts)}
  end

  @doc """
  Implementation for `Ecto.Repo.update/2`.
  """
  def update(repo, name, %Changeset{} = changeset, opts) when is_list(opts) do
    do_update(repo, name, changeset, opts)
  end

  def update(_repo, _name, %{__struct__: _}, opts) when is_list(opts) do
    raise ArgumentError, "giving a struct to Ecto.Repo.update/2 is not supported. " <>
                         "Ecto is unable to properly track changes when a struct is given, " <>
                         "an Ecto.Changeset must be given instead"
  end

  defp do_update(repo, name, %Changeset{valid?: true} = changeset, opts) do
    {adapter, adapter_meta} = Ecto.Repo.Registry.lookup(name)
    %{prepare: prepare, repo_opts: repo_opts} = changeset
    opts = Keyword.merge(repo_opts, opts)

    struct = struct_from_changeset!(:update, changeset)
    schema = struct.__struct__
    dumper = schema.__schema__(:dump)
    fields = schema.__schema__(:fields)
    assocs = schema.__schema__(:associations)
    embeds = schema.__schema__(:embeds)

    force? = !!opts[:force]
    filters = add_pk_filter!(changeset.filters, struct)

    {return_types, return_sources} =
      schema
      |> returning(opts)
      |> add_read_after_writes(schema)
      |> fields_to_sources(dumper)

    # Differently from insert, update does not copy the struct
    # fields into the changeset. All changes must be in the
    # changeset before hand.
    changeset = put_repo_and_action(changeset, :update, repo, opts)

    if changeset.changes != %{} or changeset.repo_changes != %{} or force? do
      wrap_in_transaction(adapter, adapter_meta, opts, changeset, assocs, embeds, prepare, fn ->
        assoc_opts = assoc_opts(assocs, opts)
        user_changeset = run_prepare(changeset, prepare)

        {changeset, parents, children} = pop_assocs(user_changeset, assocs)
        changeset = process_parents(changeset, parents, adapter, assoc_opts)
        changeset = repo_changes(changeset)

        if changeset.valid? do
          embeds = Ecto.Embedded.prepare(changeset, embeds, adapter, :update)

          original = changeset.changes |> Map.merge(embeds) |> Map.take(fields)
          {changes, autogen} = dump_changes!(:update, original, schema, [], dumper, adapter)

          schema_meta = metadata(struct, schema.__schema__(:autogenerate_id), opts)
          filters = dump_fields!(:update, schema, filters, dumper, adapter)
          args = [adapter_meta, schema_meta, changes, filters, return_sources, opts]

          # If there are no changes or all the changes were autogenerated but not forced, we skip
          {action, autogen} =
            if original != %{} or (autogen != [] and force?),
               do: {:update, autogen},
               else: {:noop, []}

          case apply(user_changeset, adapter, action, args) do
            {:ok, values} ->
              changeset
              |> load_changes(:loaded, return_types, values, embeds, autogen, adapter, schema_meta)
              |> process_children(children, user_changeset, adapter, assoc_opts)

            {:error, _} = error ->
              error
          end
        else
          {:error, changeset}
        end
      end)
    else
      {:ok, changeset.data}
    end
  end

  defp do_update(repo, _name, %Changeset{valid?: false} = changeset, opts) do
    {:error, put_repo_and_action(changeset, :update, repo, opts)}
  end

  @doc """
  Implementation for `Ecto.Repo.insert_or_update/2`.
  """
  def insert_or_update(repo, name, changeset, opts) do
    case get_state(changeset) do
      :built  -> insert(repo, name, changeset, opts)
      :loaded -> update(repo, name, changeset, opts)
      state   -> raise ArgumentError, "the changeset has an invalid state " <>
                                      "for Repo.insert_or_update/2: #{state}"
    end
  end

  @doc """
  Implementation for `Ecto.Repo.insert_or_update!/2`.
  """
  def insert_or_update!(repo, name, changeset, opts) do
    case get_state(changeset) do
      :built  -> insert!(repo, name, changeset, opts)
      :loaded -> update!(repo, name, changeset, opts)
      state   -> raise ArgumentError, "the changeset has an invalid state " <>
                                      "for Repo.insert_or_update!/2: #{state}"
    end
  end

  defp get_state(%Changeset{data: %{__meta__: %{state: state}}}), do: state
  defp get_state(%{__struct__: _}) do
    raise ArgumentError, "giving a struct to Repo.insert_or_update/2 or " <>
                         "Repo.insert_or_update!/2 is not supported. " <>
                         "Please use an Ecto.Changeset"
  end

  @doc """
  Implementation for `Ecto.Repo.delete/2`.
  """
  def delete(repo, name, %Changeset{} = changeset, opts) when is_list(opts) do
    do_delete(repo, name, changeset, opts)
  end

  def delete(repo, name, %{__struct__: _} = struct, opts) when is_list(opts) do
    changeset = Ecto.Changeset.change(struct)
    do_delete(repo, name, changeset, opts)
  end

  defp do_delete(repo, name, %Changeset{valid?: true} = changeset, opts) do
    {adapter, adapter_meta} = Ecto.Repo.Registry.lookup(name)
    %{prepare: prepare, repo_opts: repo_opts} = changeset
    opts = Keyword.merge(repo_opts, opts)

    struct = struct_from_changeset!(:delete, changeset)
    schema = struct.__struct__
    assocs = to_delete_assocs(schema)
    dumper = schema.__schema__(:dump)
    changeset = put_repo_and_action(changeset, :delete, repo, opts)

    wrap_in_transaction(adapter, adapter_meta, opts, assocs != [], prepare, fn ->
      changeset = run_prepare(changeset, prepare)

      filters = add_pk_filter!(changeset.filters, struct)
      filters = dump_fields!(:delete, schema, filters, dumper, adapter)

      # Delete related associations
      for %{__struct__: mod, on_delete: on_delete} = reflection <- assocs do
        apply(mod, on_delete, [reflection, changeset.data, name, opts])
      end

      schema_meta = metadata(struct, schema.__schema__(:autogenerate_id), opts)
      args = [adapter_meta, schema_meta, filters, opts]

      case apply(changeset, adapter, :delete, args) do
        {:ok, values} ->
          changeset = load_changes(changeset, :deleted, [], values, %{}, [], adapter, schema_meta)
          {:ok, changeset.data}

        {:error, _} = error ->
          error
      end
    end)
  end

  defp do_delete(repo, _name, %Changeset{valid?: false} = changeset, opts) do
    {:error, put_repo_and_action(changeset, :delete, repo, opts)}
  end

  def load(adapter, schema_or_types, data) do
    do_load(schema_or_types, data, &Ecto.Type.adapter_load(adapter, &1, &2))
  end

  defp do_load(schema, data, loader) when is_list(data),
    do: do_load(schema, Map.new(data), loader)
  defp do_load(schema, {fields, values}, loader) when is_list(fields) and is_list(values),
    do: do_load(schema, Enum.zip(fields, values), loader)
  defp do_load(schema, data, loader) when is_atom(schema),
    do: Ecto.Schema.Loader.unsafe_load(schema, data, loader)
  defp do_load(types, data, loader) when is_map(types),
    do: Ecto.Schema.Loader.unsafe_load(%{}, types, data, loader)

  ## Helpers

  defp returning(schema, opts) do
    case Keyword.get(opts, :returning, false) do
      [_ | _] = fields ->
        fields
      [] ->
        raise ArgumentError, ":returning expects at least one field to be given, got an empty list"
      true when is_nil(schema) ->
        raise ArgumentError, ":returning option can only be set to true if a schema is given"
      true ->
        schema.__schema__(:fields)
      false ->
        []
    end
  end

  defp add_read_after_writes([], schema),
    do: schema.__schema__(:read_after_writes)

  defp add_read_after_writes(return, schema),
    do: Enum.uniq(return ++ schema.__schema__(:read_after_writes))

  defp fields_to_sources(fields, nil) do
    {fields, fields}
  end
  defp fields_to_sources(fields, dumper) do
    Enum.reduce(fields, {[], []}, fn field, {types, sources} ->
      {source, type} = Map.fetch!(dumper, field)
      {[{field, type} | types], [source | sources]}
    end)
  end

  defp repo_changes(%{repo_changes: repo_changes} = changeset) do
    if repo_changes == %{} do
      changeset
    else
      update_in(changeset.changes, &Map.merge(&1, repo_changes))
    end
  end

  defp struct_from_changeset!(action, %{data: nil}),
    do: raise(ArgumentError, "cannot #{action} a changeset without :data")
  defp struct_from_changeset!(_action, %{data: struct}),
    do: struct

  defp put_repo_and_action(%{action: :ignore, valid?: valid?} = changeset, action, repo, opts) do
    if valid? do
      raise ArgumentError, "a valid changeset with action :ignore was given to " <>
                           "#{inspect repo}.#{action}/2. Changesets can only be ignored " <>
                           "in a repository action if they are also invalid"
    else
      %{changeset | action: action, repo: repo, repo_opts: opts}
    end
  end
  defp put_repo_and_action(%{action: given}, action, repo, _opts) when given != nil and given != action,
    do: raise ArgumentError, "a changeset with action #{inspect given} was given to #{inspect repo}.#{action}/2"
  defp put_repo_and_action(changeset, action, repo, opts),
    do: %{changeset | action: action, repo: repo, repo_opts: opts}

  defp run_prepare(changeset, prepare) do
    Enum.reduce(Enum.reverse(prepare), changeset, fn fun, acc ->
      case fun.(acc) do
        %Ecto.Changeset{} = acc -> acc
        other ->
          raise "expected function #{inspect fun} given to Ecto.Changeset.prepare_changes/2 " <>
                "to return an Ecto.Changeset, got: `#{inspect other}`"
      end
    end)
  end

  defp metadata(schema, prefix, source, autogen_id, context, opts) do
    %{
      autogenerate_id: autogen_id,
      context: context,
      schema: schema,
      source: source,
      prefix: Keyword.get(opts, :prefix, prefix)
    }
  end
  defp metadata(%{__struct__: schema, __meta__: %{context: context, source: source, prefix: prefix}},
                autogen_id, opts) do
    metadata(schema, prefix, source, autogen_id, context, opts)
  end
  defp metadata(%{__struct__: schema}, _, _) do
    raise ArgumentError, "#{inspect(schema)} needs to be a schema with source"
  end

  defp conflict_target({:constraint, constraint}, _dumper) when is_atom(constraint) do
    IO.warn "{:constraint, constraint} option for :conflict_target is deprecated, " <>
              "use {:unsafe_fragment, \"ON CONSTRAINT #{constraint}\" instead"
    {:constraint, constraint}
  end
  defp conflict_target({:unsafe_fragment, fragment}, _dumper) when is_binary(fragment) do
    {:unsafe_fragment, fragment}
  end
  defp conflict_target(conflict_target, dumper) do
    for target <- List.wrap(conflict_target) do
      case dumper do
        %{^target => {alias, _}} ->
          alias
        %{} when is_atom(target) ->
          raise ArgumentError, "unknown field `#{inspect(target)}` in conflict_target"
        _ ->
          target
      end
    end
  end

  defp on_conflict(on_conflict, conflict_target, schema_meta, counter_fun, adapter) do
    %{source: source, schema: schema, prefix: prefix} = schema_meta

    case on_conflict do
      :raise when conflict_target == [] ->
        {:raise, [], []}

      :raise ->
        raise ArgumentError, ":conflict_target option is forbidden when :on_conflict is :raise"

      :nothing ->
        {:nothing, [], conflict_target}

      {:replace, keys} when is_list(keys) and conflict_target == [] ->
        raise ArgumentError, ":conflict_target option is required when :on_conflict is replace"

      {:replace, keys} when is_list(keys) ->
        fields = Enum.map(keys, &field_source!(schema, &1))
        {fields, [], conflict_target}

      :replace_all ->
        {replace_all_fields!(:replace_all, schema, []), [], conflict_target}

      {:replace_all_except, fields} ->
        {replace_all_fields!(:replace_all_except, schema, fields), [], conflict_target}

      :replace_all_except_primary_key ->
        # TODO: Remove me in future versions
        IO.warn ":replace_all_except_primary_key is deprecated, please use {:replace_all_except, [...]} instead"
        fields = replace_all_fields!(:replace_all_except_primary_key, schema, schema && schema.__schema__(:primary_key))
        {fields, [], conflict_target}

      [_ | _] = on_conflict ->
        from = if schema, do: {source, schema}, else: source
        query = Ecto.Query.from from, update: ^on_conflict
        on_conflict_query(query, {source, schema}, prefix, counter_fun, adapter, conflict_target)

      %Ecto.Query{} = query ->
        on_conflict_query(query, {source, schema}, prefix, counter_fun, adapter, conflict_target)

      other ->
        raise ArgumentError, "unknown value for :on_conflict, got: #{inspect other}"
    end
  end

  defp replace_all_fields!(kind, nil, _to_remove) do
    raise ArgumentError, "cannot use #{inspect(kind)} on operations without a schema"
  end

  defp replace_all_fields!(_kind, schema, to_remove) do
    Enum.map(schema.__schema__(:fields) -- to_remove, &field_source!(schema, &1))
  end

  defp field_source!(nil, field) do
    field
  end

  defp field_source!(schema, field) do
    schema.__schema__(:field_source, field) ||
      raise ArgumentError, "unknown field for :on_conflict, got: #{inspect(field)}"
  end

  defp on_conflict_query(query, from, prefix, counter_fun, adapter, conflict_target) do
    {query, params, _} =
      Ecto.Query.Planner.plan(%{query | prefix: prefix}, :update_all, adapter)

    unless query.from.source == from do
      raise ArgumentError, "cannot run on_conflict: query because the query " <>
                           "has a different {source, schema} pair than the " <>
                           "original struct/changeset/query. Got #{inspect query.from} " <>
                           "and #{inspect from} respectively"
    end

    {query, _} = Ecto.Query.Planner.normalize(query, :update_all, adapter, counter_fun.())
    {query, params, conflict_target}
  end

  defp apply(_user_changeset, _adapter, :noop, _args) do
    {:ok, []}
  end

  defp apply(user_changeset, adapter, action, args) do
    case apply(adapter, action, args) do
      {:ok, values} ->
        {:ok, values}

      {:invalid, constraints} ->
        {:error, constraints_to_errors(user_changeset, action, constraints)}

      {:error, :stale} ->
        opts = List.last(args)

        case Keyword.fetch(opts, :stale_error_field) do
          {:ok, stale_error_field} when is_atom(stale_error_field) ->
            stale_message = Keyword.get(opts, :stale_error_message, "is stale")
            user_changeset = Changeset.add_error(user_changeset, stale_error_field, stale_message, [stale: true])
            {:error, user_changeset}

          _other ->
            raise Ecto.StaleEntryError, struct: user_changeset.data, action: action
        end
    end
  end

  defp constraints_to_errors(%{constraints: user_constraints, errors: errors} = changeset, action, constraints) do
    constraint_errors =
      Enum.map constraints, fn {type, constraint} ->
        user_constraint =
          Enum.find(user_constraints, fn c ->
            case {c.type, c.constraint,  c.match} do
              {^type, ^constraint, :exact} -> true
              {^type, cc, :suffix} -> String.ends_with?(constraint, cc)
              {^type, cc, :prefix} -> String.starts_with?(constraint, cc)
              _ -> false
            end
          end)

        case user_constraint do
          %{field: field, error_message: error_message, error_type: error_type} ->
            {field, {error_message, [constraint: error_type, constraint_name: constraint]}}
          nil ->
            raise Ecto.ConstraintError, action: action, type: type,
                                        constraint: constraint, changeset: changeset
        end
      end

    %{changeset | errors: constraint_errors ++ errors, valid?: false}
  end

  defp surface_changes(%{changes: changes, types: types} = changeset, struct, fields) do
    {changes, errors} =
      Enum.reduce fields, {changes, []}, fn field, {changes, errors} ->
        case {struct, changes, types} do
          # User has explicitly changed it
          {_, %{^field => _}, _} ->
            {changes, errors}

          # Handle associations specially
          {_, _, %{^field => {tag, embed_or_assoc}}} when tag in [:assoc, :embed] ->
            # This is partly reimplementing the logic behind put_relation
            # in Ecto.Changeset but we need to do it in a way where we have
            # control over the current value.
            value = Relation.load!(struct, Map.get(struct, field))
            empty = Relation.empty(embed_or_assoc)
            case Relation.change(embed_or_assoc, value, empty) do
              {:ok, change, _} when change != empty ->
                {Map.put(changes, field, change), errors}
              {:error, error} ->
                {changes, [{field, error}]}
              _ -> # :ignore or ok with change == empty
                {changes, errors}
            end

          # Struct has a non nil value
          {%{^field => value}, _, %{^field => _}} when value != nil ->
            {Map.put(changes, field, value), errors}

          {_, _, _} ->
            {changes, errors}
        end
      end

    case errors do
      [] -> %{changeset | changes: changes}
      _  -> %{changeset | errors: errors ++ changeset.errors, valid?: false, changes: changes}
    end
  end

  defp load_changes(changeset, state, types, values, embeds, autogen, adapter, schema_meta) do
    %{data: data, changes: changes} = changeset

    data =
      data
      |> merge_changes(changes)
      |> Map.merge(embeds)
      |> merge_autogen(autogen)
      |> apply_metadata(state, schema_meta)
      |> load_each(values, types, adapter)

    Map.put(changeset, :data, data)
  end

  defp merge_changes(data, changes) do
    changes =
      Enum.reduce(changes, changes, fn {key, _value}, changes ->
        if Map.has_key?(data, key), do: changes, else: Map.delete(changes, key)
      end)

    Map.merge(data, changes)
  end

  defp merge_autogen(data, autogen) do
    Enum.reduce(autogen, data, fn {k, v}, acc -> %{acc | k => v} end)
  end

  defp apply_metadata(%{__meta__: meta} = data, state, %{source: source, prefix: prefix}) do
    %{data | __meta__: %{meta | state: state, source: source, prefix: prefix}}
  end

  defp load_each(struct, [{_, value} | kv], [{key, type} | types], adapter) do
    case Ecto.Type.adapter_load(adapter, type, value) do
      {:ok, value} ->
        load_each(%{struct | key => value}, kv, types, adapter)
      :error ->
        raise ArgumentError, "cannot load `#{inspect value}` as type #{inspect type} " <>
                             "for field `#{key}` in schema #{inspect struct.__struct__}"
    end
  end
  defp load_each(struct, [], _types, _adapter) do
    struct
  end

  defp pop_assocs(changeset, []) do
    {changeset, [], []}
  end
  defp pop_assocs(%{changes: changes, types: types} = changeset, assocs) do
    {changes, parent, child} =
      Enum.reduce assocs, {changes, [], []}, fn assoc, {changes, parent, child} ->
        case Map.fetch(changes, assoc) do
          {:ok, value} ->
            changes = Map.delete(changes, assoc)

            case Map.fetch!(types, assoc) do
              {:assoc, %{relationship: :parent} = refl} ->
                {changes, [{refl, value}|parent], child}
              {:assoc, %{relationship: :child} = refl} ->
                {changes, parent, [{refl, value}|child]}
            end
          :error ->
            {changes, parent, child}
        end
      end
    {%{changeset | changes: changes}, parent, child}
  end

  # Don't mind computing options if there are no assocs
  defp assoc_opts([], _opts), do: []

  defp assoc_opts(_assocs, opts) do
    Keyword.take(opts, [:timeout, :log, :telemetry_event, :prefix])
  end

  defp process_parents(%{changes: changes} = changeset, assocs, adapter, opts) do
    case Ecto.Association.on_repo_change(changeset, assocs, adapter, opts) do
      {:ok, struct} ->
        changes = change_parents(changes, struct, assocs)
        %{changeset | changes: changes, data: struct}
      {:error, changes} ->
        %{changeset | changes: changes, valid?: false}
    end
  end

  defp change_parents(changes, struct, assocs) do
    Enum.reduce assocs, changes, fn {refl, _}, acc ->
      %{field: field, owner_key: owner_key, related_key: related_key} = refl
      related = Map.get(struct, field)
      value = related && Map.fetch!(related, related_key)
      case Map.fetch(changes, owner_key) do
        {:ok, current} when current != value ->
          raise ArgumentError,
            "cannot change belongs_to association `#{field}` because there is " <>
            "already a change setting its foreign key `#{owner_key}` to `#{inspect current}`"
        _ ->
          Map.put(acc, owner_key, value)
      end
    end
  end

  defp process_children(changeset, assocs, user_changeset, adapter, opts) do
    case Ecto.Association.on_repo_change(changeset, assocs, adapter, opts) do
      {:ok, struct} -> {:ok, struct}
      {:error, changes} ->
        {:error, %{user_changeset | valid?: false, changes: changes}}
    end
  end

  defp to_delete_assocs(schema) do
    for assoc <- schema.__schema__(:associations),
        reflection = schema.__schema__(:association, assoc),
        match?(%{on_delete: on_delete} when on_delete != :nothing, reflection),
        do: reflection
  end

  defp autogenerate_id(nil, changes, return_types, return_sources, _adapter) do
    {changes, [], return_types, return_sources}
  end

  defp autogenerate_id({key, source, type}, changes, return_types, return_sources, adapter) do
    cond do
      Map.has_key?(changes, key) -> # Set by user
        {changes, [], return_types, return_sources}
      value = Ecto.Type.adapter_autogenerate(adapter, type) -> # Autogenerated now
        {changes, [{source, value}], [{key, type} | return_types], return_sources}
      true -> # Autogenerated in storage
        {changes, [], [{key, type} | return_types], [source | List.delete(return_sources, source)]}
    end
  end

  defp dump_changes!(action, changes, schema, extra, dumper, adapter) do
    autogen = autogenerate_changes(schema, action, changes)
    dumped =
      dump_fields!(action, schema, changes, dumper, adapter) ++
      dump_fields!(action, schema, autogen, dumper, adapter) ++
      extra
    {dumped, autogen}
  end

  defp autogenerate_changes(schema, action, changes) do
    autogen_fields = action |> action_to_auto() |> schema.__schema__()

    Enum.flat_map(autogen_fields, fn {fields, {mod, fun, args}} ->
      case Enum.reject(fields, &Map.has_key?(changes, &1)) do
        [] ->
          []

        fields ->
          generated = apply(mod, fun, args)
          Enum.map(fields, &{&1, generated})
      end
    end)
  end

  defp action_to_auto(:insert), do: :autogenerate
  defp action_to_auto(:update), do: :autoupdate

  defp add_pk_filter!(filters, struct) do
    Enum.reduce Ecto.primary_key!(struct), filters, fn
      {_k, nil}, _acc ->
        raise Ecto.NoPrimaryKeyValueError, struct: struct
      {k, v}, acc ->
        Map.put(acc, k, v)
    end
  end

  defp wrap_in_transaction(adapter, adapter_meta, opts, changeset, assocs, embeds, prepare, fun) do
    %{changes: changes} = changeset
    changed = &Map.has_key?(changes, &1)
    relations_changed? = Enum.any?(assocs, changed) or Enum.any?(embeds, changed)
    wrap_in_transaction(adapter, adapter_meta, opts, relations_changed?, prepare, fun)
  end

  defp wrap_in_transaction(adapter, adapter_meta, opts, relations_changed?, prepare, fun) do
    if (relations_changed? or prepare != []) and
       function_exported?(adapter, :transaction, 3) and
       not adapter.in_transaction?(adapter_meta) do
      adapter.transaction(adapter_meta, opts, fn ->
        case fun.() do
          {:ok, struct} -> struct
          {:error, changeset} -> adapter.rollback(adapter_meta, changeset)
        end
      end)
    else
      fun.()
    end
  end

  defp dump_field!(action, schema, field, type, value, adapter) do
    case Ecto.Type.adapter_dump(adapter, type, value) do
      {:ok, value} ->
        value
      :error ->
        raise Ecto.ChangeError,
              "value `#{inspect(value)}` for `#{inspect(schema)}.#{field}` " <>
              "in `#{action}` does not match type #{inspect type}"
    end
  end

  defp dump_fields!(action, schema, kw, dumper, adapter) do
    for {field, value} <- kw do
      {alias, type} = Map.fetch!(dumper, field)
      {alias, dump_field!(action, schema, field, type, value, adapter)}
    end
  end
end
