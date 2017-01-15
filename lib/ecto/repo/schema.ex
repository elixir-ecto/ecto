defmodule Ecto.Repo.Schema do
  # The module invoked by user defined repos
  # for schema related functionality.
  @moduledoc false

  alias Ecto.Changeset
  alias Ecto.Changeset.Relation
  require Ecto.Query

  @doc """
  Implementation for `Ecto.Repo.insert!/2`.
  """
  def insert_all(repo, adapter, schema, rows, opts) when is_atom(schema) do
    do_insert_all(repo, adapter, schema, schema.__schema__(:prefix),
                  schema.__schema__(:source), rows, opts)
  end

  def insert_all(repo, adapter, table, rows, opts) when is_binary(table) do
    do_insert_all(repo, adapter, nil, nil, table, rows, opts)
  end

  def insert_all(repo, adapter, {prefix, source}, rows, opts) when is_binary(source) do
    IO.puts :stderr, "warning: passing {prefix, source} to insert_all is deprecated, " <>
                     "please pass the :prefix option instead\n" <> Exception.format_stacktrace
    do_insert_all(repo, adapter, nil, prefix, source, rows, opts)
  end

  def insert_all(repo, adapter, {source, schema}, rows, opts) when is_atom(schema) do
    do_insert_all(repo, adapter, schema, schema.__schema__(:prefix), source, rows, opts)
  end

  defp do_insert_all(_repo, _adapter, _schema, _prefix, _source, [], opts) do
    if opts[:returning] do
      {0, []}
    else
      {0, nil}
    end
  end

  defp do_insert_all(repo, adapter, schema, prefix, source, rows, opts) when is_list(rows) do
    returning = opts[:returning] || false
    autogen   = schema && schema.__schema__(:autogenerate_id)
    source    = {Keyword.get(opts, :prefix, prefix), source}
    fields    = preprocess(returning, schema)

    {rows, header} = extract_header_and_fields(rows, schema, autogen, adapter)
    counter = fn -> Enum.reduce(rows, 0, &length(&1) + &2) end
    metadata = %{source: source, context: nil, schema: schema, autogenerate_id: autogen}

    {on_conflict, opts} = Keyword.pop(opts, :on_conflict, :raise)
    {conflict_target, opts} = Keyword.pop(opts, :conflict_target, [])
    on_conflict = on_conflict(on_conflict, conflict_target, metadata, counter, adapter)

    {count, rows} =
      adapter.insert_all(repo, metadata, Map.keys(header), rows, on_conflict, fields || [], opts)
    {count, postprocess(rows, fields, adapter, schema, source)}
  end

  defp preprocess([_|_] = fields, _schema),
    do: fields
  defp preprocess([], _schema),
    do: raise ArgumentError, ":returning expects at least one field to be given, got an empty list"
  defp preprocess(true, nil),
    do: raise ArgumentError, ":returning option can only be set to true if a schema is given"
  defp preprocess(true, schema),
    do: schema.__schema__(:fields)
  defp preprocess(false, _schema),
    do: false

  defp postprocess(nil, false, _adapter, _schema, _source), do: nil
  defp postprocess(rows, fields, _adapter, nil, _source) do
    Enum.map(rows, &Map.new(Enum.zip(fields, &1)))
  end
  defp postprocess(rows, fields, adapter, schema, {prefix, source}) do
    Enum.map(rows, fn row ->
      Ecto.Schema.__load__(schema, prefix, source, nil, {fields, row},
                           &Ecto.Type.adapter_load(adapter, &1, &2))
    end)
  end

  defp extract_header_and_fields(rows, schema, autogenerate_id, adapter) do
    header = init_header(autogenerate_id)
    mapper = init_mapper(schema, adapter)

    Enum.map_reduce(rows, header, fn fields, header ->
      {fields, header} = Enum.map_reduce(fields, header, mapper)
      {autogenerate_id(autogenerate_id, fields, adapter), header}
    end)
  end

  defp init_header(nil), do: %{}
  defp init_header({key, _}), do: %{key => true}

  defp init_mapper(nil, _adapter) do
    fn {field, value}, acc ->
      case Ecto.DataType.dump(value) do
        {:ok, value} ->
          {{field, value}, Map.put(acc, field, true)}
        :error ->
          raise Ecto.ChangeError,
            message: "value `#{inspect value}` cannot be dumped with Ecto.DataType"
      end
    end
  end
  defp init_mapper(schema, adapter) do
    types = schema.__changeset__
    fn {field, value}, acc ->
      type = Map.fetch!(types, field)
      {dump_field!(:insert_all, schema, field, type, value, adapter),
       Map.put(acc, field, true)}
    end
  end

  defp autogenerate_id(nil, fields, _adapter), do: fields
  defp autogenerate_id({key, type}, fields, adapter) do
    case :lists.keyfind(key, 1, fields) do
      {^key, _} -> fields
      false ->
        if value = adapter.autogenerate(type) do
          [{key, value}|fields]
        else
          fields
        end
    end
  end

  @doc """
  Implementation for `Ecto.Repo.insert!/2`.
  """
  def insert!(repo, adapter, struct_or_changeset, opts) do
    case insert(repo, adapter, struct_or_changeset, opts) do
      {:ok, struct} -> struct
      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
    end
  end

  @doc """
  Implementation for `Ecto.Repo.update!/2`.
  """
  def update!(repo, adapter, struct_or_changeset, opts) do
    case update(repo, adapter, struct_or_changeset, opts) do
      {:ok, struct} -> struct
      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :update, changeset: changeset
    end
  end

  @doc """
  Implementation for `Ecto.Repo.delete!/2`.
  """
  def delete!(repo, adapter, struct_or_changeset, opts) do
    case delete(repo, adapter, struct_or_changeset, opts) do
      {:ok, struct} -> struct
      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :delete, changeset: changeset
    end
  end

  @doc """
  Implementation for `Ecto.Repo.insert/2`.
  """
  def insert(repo, adapter, %Changeset{} = changeset, opts) when is_list(opts) do
    do_insert(repo, adapter, changeset, opts)
  end

  def insert(repo, adapter, %{__struct__: _} = struct, opts) when is_list(opts) do
    changeset = Ecto.Changeset.change(struct)
    do_insert(repo, adapter, changeset, opts)
  end

  defp do_insert(repo, adapter, %Changeset{valid?: true} = changeset, opts) do
    %{prepare: prepare, types: types} = changeset
    struct = struct_from_changeset!(:insert, changeset)
    schema = struct.__struct__
    fields = schema.__schema__(:fields)
    assocs = schema.__schema__(:associations)
    return = schema.__schema__(:read_after_writes)

    {on_conflict, opts} = Keyword.pop(opts, :on_conflict, :raise)
    {conflict_target, opts} = Keyword.pop(opts, :conflict_target, [])

    # On insert, we always merge the whole struct into the
    # changeset as changes, except the primary key if it is nil.
    changeset = put_repo_and_action(changeset, :insert, repo)
    changeset = surface_changes(changeset, struct, types, fields ++ assocs)

    wrap_in_transaction(repo, adapter, opts, assocs, prepare, fn ->
      opts = Keyword.put(opts, :skip_transaction, true)
      user_changeset = run_prepare(changeset, prepare)

      {changeset, parents, children} = pop_assocs(user_changeset, assocs)
      changeset = process_parents(changeset, parents, opts)

      if changeset.valid? do
        changeset = Ecto.Embedded.prepare(changeset, adapter, :insert)

        metadata = metadata(struct, opts)
        {changes, extra, return} = autogenerate_id(metadata, changeset.changes, return, adapter)
        {changes, autogen} = dump_changes!(:insert, Map.take(changes, fields), schema, extra, types, adapter)

        on_conflict = on_conflict(on_conflict, conflict_target, metadata,
                                  fn -> length(changes) end, adapter)
        args = [repo, metadata, changes, on_conflict, return, opts]
        case apply(changeset, adapter, :insert, args) do
          {:ok, values} ->
            changeset
            |> load_changes(:loaded, values ++ extra, autogen, adapter)
            |> process_children(children, user_changeset, opts)
          {:error, _} = error ->
            error
          {:invalid, constraints} ->
            {:error, constraints_to_errors(user_changeset, :insert, constraints)}
        end
      else
        {:error, changeset}
      end
    end)
  end

  defp do_insert(repo, _adapter, %Changeset{valid?: false} = changeset, _opts) do
    {:error, put_repo_and_action(changeset, :insert, repo)}
  end

  @doc """
  Implementation for `Ecto.Repo.update/2`.
  """
  def update(repo, adapter, %Changeset{} = changeset, opts) when is_list(opts) do
    do_update(repo, adapter, changeset, opts)
  end

  def update(repo, _adapter, %{__struct__: _}, opts) when is_list(opts) do
    raise ArgumentError, "giving a struct to #{inspect repo}.update/2 is not supported. " <>
                         "Ecto is unable to properly track changes when a struct is given, " <>
                         "an Ecto.Changeset must be given instead"
  end

  defp do_update(repo, adapter, %Changeset{valid?: true} = changeset, opts) do
    %{prepare: prepare, types: types} = changeset
    struct = struct_from_changeset!(:update, changeset)
    schema = struct.__struct__
    fields = schema.__schema__(:fields)
    assocs = schema.__schema__(:associations)
    return = schema.__schema__(:read_after_writes)
    force? = !!opts[:force]
    filters = add_pk_filter!(changeset.filters, struct)

    # Differently from insert, update does not copy the struct
    # fields into the changeset. All changes must be in the
    # changeset before hand.
    changeset = put_repo_and_action(changeset, :update, repo)

    if changeset.changes != %{} or force? do
      wrap_in_transaction(repo, adapter, opts, assocs, prepare, fn ->
        opts = Keyword.put(opts, :skip_transaction, true)
        user_changeset = run_prepare(changeset, prepare)

        {changeset, parents, children} = pop_assocs(user_changeset, assocs)
        changeset = process_parents(changeset, parents, opts)

        if changeset.valid? do
          changeset = Ecto.Embedded.prepare(changeset, adapter, :update)

          original =  Map.take(changeset.changes, fields)
          {changes, autogen} = dump_changes!(:update, original, schema, [], types, adapter)

          filters = dump_fields!(schema, :update, filters, types, adapter)
          args    = [repo, metadata(struct, opts), changes, filters, return, opts]

          # If there are no changes or all the changes were autogenerated but not forced, we skip
          {action, autogen} =
            if original != %{} or (autogen != [] and force?),
               do: {:update, autogen},
               else: {:noop, []}

          case apply(changeset, adapter, action, args) do
            {:ok, values} ->
              changeset
              |> load_changes(:loaded, values, autogen, adapter)
              |> process_children(children, user_changeset, opts)
            {:error, _} = error ->
              error
            {:invalid, constraints} ->
              {:error, constraints_to_errors(user_changeset, :update, constraints)}
          end
        else
          {:error, changeset}
        end
      end)
    else
      {:ok, changeset.data}
    end
  end

  defp do_update(repo, _adapter, %Changeset{valid?: false} = changeset, _opts) do
    {:error, put_repo_and_action(changeset, :update, repo)}
  end

  @doc """
  Implementation for `Ecto.Repo.insert_or_update/2`.
  """
  def insert_or_update(repo, adapter, changeset, opts) do
    case get_state(changeset) do
      :built  -> insert repo, adapter, changeset, opts
      :loaded -> update repo, adapter, changeset, opts
      state   -> raise ArgumentError, "the changeset has an invalid state " <>
                                      "for Repo.insert_or_update/2: #{state}"
    end
  end

  @doc """
  Implementation for `Ecto.Repo.insert_or_update!/2`.
  """
  def insert_or_update!(repo, adapter, changeset, opts) do
    case get_state(changeset) do
      :built  -> insert! repo, adapter, changeset, opts
      :loaded -> update! repo, adapter, changeset, opts
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
  def delete(repo, adapter, %Changeset{} = changeset, opts) when is_list(opts) do
    do_delete(repo, adapter, changeset, opts)
  end

  def delete(repo, adapter, %{__struct__: _} = struct, opts) when is_list(opts) do
    changeset = Ecto.Changeset.change(struct)
    do_delete(repo, adapter, changeset, opts)
  end

  defp do_delete(repo, adapter, %Changeset{valid?: true} = changeset, opts) do
    %{prepare: prepare, types: types} = changeset
    struct = struct_from_changeset!(:delete, changeset)
    schema  = struct.__struct__
    assocs = schema.__schema__(:associations)

    changeset = put_repo_and_action(changeset, :delete, repo)
    changeset = %{changeset | changes: %{}}

    wrap_in_transaction(repo, adapter, opts, assocs, prepare, fn ->
      changeset = run_prepare(changeset, prepare)

      filters = add_pk_filter!(changeset.filters, struct)
      filters = dump_fields!(schema, :delete, filters, types, adapter)

      delete_assocs(changeset, repo, schema, assocs, opts)
      args = [repo, metadata(struct, opts), filters, opts]
      case apply(changeset, adapter, :delete, args) do
        {:ok, values} ->
          {:ok, load_changes(changeset, :deleted, values, [], adapter).data}
        {:error, _} = error ->
          error
        {:invalid, constraints} ->
          {:error, constraints_to_errors(changeset, :delete, constraints)}
      end
    end)
  end

  defp do_delete(repo, _adapter, %Changeset{valid?: false} = changeset, _opts) do
    {:error, put_repo_and_action(changeset, :delete, repo)}
  end

  def load(adapter, schema_or_types, data) do
    do_load(schema_or_types, data, &Ecto.Type.adapter_load(adapter, &1, &2))
  end

  defp do_load(schema, data, loader) when is_list(data),
    do: do_load(schema, Map.new(data), loader)
  defp do_load(schema, {fields, values}, loader) when is_list(fields) and is_list(values),
    do: do_load(schema, Enum.zip(fields, values), loader)
  defp do_load(schema, data, loader) when is_atom(schema),
    do: Ecto.Schema.__load__(schema, nil, nil, nil, data, loader)
  defp do_load(types, data, loader) when is_map(types),
    do: Ecto.Schema.__load__(%{}, types, data, loader)

  ## Helpers

  defp struct_from_changeset!(action, %{data: nil}),
    do: raise(ArgumentError, "cannot #{action} a changeset without :data")
  defp struct_from_changeset!(_action, %{data: struct}),
    do: struct

  defp put_repo_and_action(%{action: given}, action, repo) when given != nil and given != action,
    do: raise(ArgumentError, "a changeset with action #{inspect given} was given to #{inspect repo}.#{action}/2")
  defp put_repo_and_action(changeset, action, repo),
    do: %{changeset | action: action, repo: repo}

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

  defp metadata(%{__struct__: schema, __meta__: %{context: context, source: {prefix, source}}}, opts) do
    %{autogenerate_id: schema.__schema__(:autogenerate_id),
      context: context,
      schema: schema,
      source: {Keyword.get(opts, :prefix, prefix), source}}
  end

  defp on_conflict(on_conflict, conflict_target,
                   %{source: {prefix, source}, schema: schema}, changes, adapter) do
    conflict_target = List.wrap conflict_target
    case on_conflict do
      :raise when conflict_target == [] ->
        {:raise, [], []}
      :raise ->
        raise ArgumentError, ":conflict_target option is forbidden when :on_conflict is :raise"
      :nothing ->
        {:nothing, [], conflict_target}
      :replace_all ->
        {:replace_all, [], conflict_target}
      [_ | _] = on_conflict ->
        from = if schema, do: {source, schema}, else: source
        query = Ecto.Query.from from, update: ^on_conflict
        on_conflict_query(query, {source, schema}, prefix, changes, adapter, conflict_target)
      %Ecto.Query{} = query ->
        on_conflict_query(query, {source, schema}, prefix, changes, adapter, conflict_target)
      other ->
        raise ArgumentError, "unknown value for :on_conflict, got: #{inspect other}"
    end
  end

  defp on_conflict_query(query, from, prefix, changes, adapter, conflict_target) do
    counter = changes.()

    {query, params, _} =
      %{query | prefix: prefix}
      |> Ecto.Query.Planner.assert_no_select!(:update_all)
      |> Ecto.Query.Planner.returning(false)
      |> Ecto.Query.Planner.prepare(:update_all, adapter, counter)

    unless query.from == from do
      raise ArgumentError, "cannot run on_conflict: query because the query " <>
                           "has a different {source, schema} pair than the " <>
                           "original struct/changeset/query. Got #{inspect query.from} " <>
                           "and #{inspect from} respectively"
    end

    {Ecto.Query.Planner.normalize(query, :update_all, adapter, counter),
     params, conflict_target}
  end

  defp apply(%{valid?: false} = changeset, _adapter, _action, _args) do
    {:error, changeset}
  end
  defp apply(_changeset, _adapter, :noop, _args) do
    {:ok, []}
  end
  defp apply(changeset, adapter, action, args) do
    case apply(adapter, action, args) do
      {:ok, values} ->
        {:ok, values}
      {:invalid, _} = constraints ->
        constraints
      {:error, :stale} ->
        raise Ecto.StaleEntryError, struct: changeset.data, action: action
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
              _ -> false
            end
          end)

        case user_constraint do
          %{field: field, error: error} ->
            {field, error}
          nil ->
            raise Ecto.ConstraintError, action: action, type: type,
                                        constraint: constraint, changeset: changeset
        end
      end

    %{changeset | errors: constraint_errors ++ errors, valid?: false}
  end

  defp surface_changes(%{changes: changes} = changeset, struct, types, fields) do
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
              {:ok, change, _, false} when change != empty ->
                {Map.put(changes, field, change), errors}
              {:ok, _, _, _} ->
                {changes, errors}
              :error ->
                {changes, [{field, "is invalid"}]}
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

  defp load_changes(%{types: types, changes: changes} = changeset, state, values, autogen, adapter) do
    # It is ok to use types from changeset because we have
    # already filtered the results to be only about fields.
    data =
      changeset.data
      |> merge_changes(changes)
      |> merge_autogen(autogen)
      |> load_each(values, types, adapter)
    data = put_in(data.__meta__.state, state)
    Map.put(changeset, :data, data)
  end

  defp merge_changes(data, changes),
    do: Map.merge(data, changes)
  defp merge_autogen(data, autogen),
    do: Enum.reduce(autogen, data, fn {k, v}, acc -> Map.put(acc, k, v) end)

  defp load_each(struct, kv, types, adapter) do
    Enum.reduce(kv, struct, fn {k, v}, acc ->
      type = Map.fetch!(types, k)
      case Ecto.Type.adapter_load(adapter, type, v) do
        {:ok, v} -> Map.put(acc, k, v)
        :error   -> raise ArgumentError, "cannot load `#{inspect v}` as type #{inspect type}"
      end
    end)
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

  defp process_parents(%{changes: changes} = changeset, assocs, opts) do
    case Ecto.Association.on_repo_change(changeset, assocs, opts) do
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
      value   = related && Map.get(related, related_key)
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

  defp process_children(changeset, assocs, user_changeset, opts) do
    case Ecto.Association.on_repo_change(changeset, assocs, opts) do
      {:ok, struct} -> {:ok, struct}
      {:error, changes} ->
        {:error, %{user_changeset | valid?: false, changes: changes}}
    end
  end

  defp delete_assocs(%{data: struct}, repo, schema, assocs, opts) do
    for assoc_name <- assocs do
      case schema.__schema__(:association, assoc_name) do
        %{__struct__: mod, on_delete: on_delete} = reflection when on_delete != :nothing ->
          apply(mod, on_delete, [reflection, struct, repo, opts])
        _ ->
          :ok
      end
    end
    :ok
  end

  defp autogenerate_id(%{autogenerate_id: nil}, changes, return, _adapter) do
    {changes, [], return}
  end

  defp autogenerate_id(%{autogenerate_id: {key, type}}, changes, return, adapter) do
    if Map.has_key?(changes, key) do
      {changes, [], return} # Set by user
    else
      if value = adapter.autogenerate(type) do
        {changes, [{key, value}], return} # Autogenerated now
      else
        {changes, [], [key|List.delete(return, key)]} # Autogenerated in storage
      end
    end
  end

  defp dump_changes!(action, changes, schema, extra, types, adapter) do
    autogen = autogenerate_changes(schema, action, changes)
    dumped  =
      dump_fields!(action, schema, changes, types, adapter) ++
      dump_fields!(action, schema, autogen, types, adapter) ++
      extra
    {dumped, autogen}
  end

  defp autogenerate_changes(schema, action, changes) do
    for {k, {mod, fun, args}} <- schema.__schema__(action_to_auto(action)),
        not Map.has_key?(changes, k),
        do: {k, apply(mod, fun, args)}
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

  defp wrap_in_transaction(repo, adapter, opts, assocs, prepare, fun) do
    if (assocs != [] or prepare != []) and
       Keyword.get(opts, :skip_transaction) != true and
       function_exported?(adapter, :transaction, 3) do
      adapter.transaction(repo, opts, fn ->
        case fun.() do
          {:ok, struct} -> struct
          {:error, changeset} -> adapter.rollback(repo, changeset)
        end
      end)
    else
      fun.()
    end
  end

  defp dump_field!(action, schema, field, type, value, adapter) do
    case Ecto.Type.adapter_dump(adapter, type, value) do
      {:ok, value} ->
        {field, value}
      :error ->
        raise Ecto.ChangeError,
          message: "value `#{inspect value}` for `#{inspect schema}.#{field}` " <>
                   "in `#{action}` does not match type #{inspect type}"
    end
  end

  defp dump_fields!(action, schema, kw, types, adapter) do
    for {field, value} <- kw do
      type = Map.fetch!(types, field)
      dump_field!(action, schema, field, type, value, adapter)
    end
  end
end
