defmodule Ecto.Repo.Model do
  # The module invoked by user defined repos
  # for model related functionality.
  @moduledoc false

  alias Ecto.Query.Planner
  alias Ecto.Model.Callbacks
  alias Ecto.Changeset

  @doc """
  Implementation for `Ecto.Repo.insert!/2`.
  """
  def insert!(repo, adapter, model_or_changeset, opts) do
    case insert(repo, adapter, model_or_changeset, opts) do
      {:ok, model} -> model
      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :insert, changeset: changeset
    end
  end

  @doc """
  Implementation for `Ecto.Repo.update!/2`.
  """
  def update!(repo, adapter, model_or_changeset, opts) do
    case update(repo, adapter, model_or_changeset, opts) do
      {:ok, model} -> model
      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :update, changeset: changeset
    end
  end

  @doc """
  Implementation for `Ecto.Repo.delete!/2`.
  """
  def delete!(repo, adapter, model_or_changeset, opts) do
    case delete(repo, adapter, model_or_changeset, opts) do
      {:ok, model} -> model
      {:error, changeset} ->
        raise Ecto.InvalidChangesetError, action: :delete, changeset: changeset
    end
  end

  @doc """
  Implementation for `Ecto.Repo.insert/2`.
  """
  def insert(repo, adapter, %Changeset{valid?: true} = changeset, opts) when is_list(opts) do
    struct   = struct_from_changeset!(:insert, changeset)
    model    = struct.__struct__
    fields   = model.__schema__(:fields)
    embeds   = model.__schema__(:embeds)
    assocs   = model.__schema__(:associations)
    {prefix, source} = struct.__meta__.source
    return   = model.__schema__(:read_after_writes)

    # On insert, we always merge the whole struct into the
    # changeset as changes, except the primary key if it is nil.
    # We also remove all embeds that are not in the changes
    changeset = %{changeset | repo: repo, action: :insert}
    changeset = insert_changes(struct, fields, embeds, changeset)

    wrap_in_transaction(repo, adapter, model, opts, embeds, assocs,
                        ~w(before_insert after_insert)a, fn ->
      changeset = Callbacks.__apply__(model, :before_insert, changeset)
      changeset = Ecto.Embedded.apply_callbacks(changeset, embeds, adapter, :insert, :before)

      {assoc_changes, changeset} = pop_from_changes(changeset, assocs)
      {autogen, changes} = pop_autogenerate_id(changeset.changes, model)
      changes = validate_changes(:insert, changes, model, fields, adapter)
      {embed_changes, changeset} = pop_from_changes(changeset, embeds)

      {:ok, values} = adapter.insert(repo, {prefix, source, model}, changes, autogen, return, opts)

      {success, changeset} =
        changeset
        |> load_changes(values, adapter)
        |> process_embeds(embed_changes, adapter, repo, opts)
        |> process_assocs(assoc_changes, adapter, repo, opts)

      changeset = put_in changeset.model.__meta__.state, :loaded

      case {success, changeset} do
        {:ok, changeset} ->
          {:ok, Callbacks.__apply__(model, :after_insert, changeset).model}
        {:error, changeset} ->
          {:error, %{changeset | valid?: false}}
      end
    end)
  end

  def insert(_repo, _adapter, %Changeset{valid?: false} = changeset, opts) when is_list(opts) do
    {:error, %{changeset | action: :insert}}
  end

  def insert(repo, adapter, %{__struct__: _} = struct, opts) when is_list(opts) do
    insert(repo, adapter, Ecto.Changeset.change(struct), opts)
  end

  @doc """
  Implementation for `Ecto.Repo.update/2`.
  """
  def update(repo, adapter, %Changeset{valid?: true} = changeset, opts) when is_list(opts) do
    struct   = struct_from_changeset!(:update, changeset)
    model    = struct.__struct__
    fields   = model.__schema__(:fields)
    embeds   = model.__schema__(:embeds)
    assocs   = model.__schema__(:associations)
    {prefix, source} = struct.__meta__.source
    return   = model.__schema__(:read_after_writes)

    # Differently from insert, update does not copy the struct
    # fields into the changeset. All changes must be in the
    # changeset before hand.
    changeset = %{changeset | repo: repo, action: :update}

    if changeset.changes != %{} or opts[:force] do
      wrap_in_transaction(repo, adapter, model, opts, embeds, assocs,
                          ~w(before_update after_update)a, fn ->
        changeset = Callbacks.__apply__(model, :before_update, changeset)
        changeset = Ecto.Embedded.apply_callbacks(changeset, embeds, adapter, :update, :before)

        {assoc_changes, changeset} = pop_from_changes(changeset, assocs)
        autogen = get_autogenerate_id(changeset.changes, model)
        changes = validate_changes(:update, changeset.changes, model, fields, adapter)
        {embed_changes, changeset} = pop_from_changes(changeset, embeds)

        filters = add_pk_filter!(changeset.filters, struct)
        filters = Planner.fields(model, :update, filters, adapter)

        values =
          if changes != [] do
            case adapter.update(repo, {prefix, source, model}, changes, filters, autogen, return, opts) do
              {:ok, values} ->
                values
              {:error, :stale} ->
                raise Ecto.StaleModelError, model: struct, action: :update
            end
          else
            []
          end

        {success, changeset} =
          changeset
          |> load_changes(values, adapter)
          |> process_embeds(embed_changes, adapter, repo, opts)
          |> process_assocs(assoc_changes, adapter, repo, opts)

        case {success, changeset} do
          {:ok, changeset} ->
            {:ok, Callbacks.__apply__(model, :after_update, changeset).model}
          {:error, changeset} ->
            {:error, %{changeset | valid?: false}}
        end
      end)
    else
      {:ok, changeset.model}
    end
  end

  def update(_repo, _adapter, %Changeset{valid?: false} = changeset, opts) when is_list(opts) do
    {:error, %{changeset | action: :update}}
  end

  def update(repo, adapter, %{__struct__: model} = struct, opts) when is_list(opts) do
    changes =
      struct
      |> Map.take(model.__schema__(:fields))
      |> Map.drop(model.__schema__(:primary_key))
      |> Map.drop(model.__schema__(:embeds))

    changeset = %{Ecto.Changeset.change(struct) | changes: changes}
    update(repo, adapter, changeset, opts)
  end

  @doc """
  Implementation for `Ecto.Repo.delete/2`.
  """
  def delete(repo, adapter, %Changeset{valid?: true} = changeset, opts) when is_list(opts) do
    struct = struct_from_changeset!(:delete, changeset)
    model  = struct.__struct__
    {prefix, source} = struct.__meta__.source
    embeds = model.__schema__(:embeds)

    changeset = %{changeset | repo: repo, action: :delete}
    autogen   = get_autogenerate_id(changeset, model)

    if changeset.changes != %{} do
      raise ArgumentError, "Repo.delete does not support changesets with " <>
        "changes, got `#{inspect changeset.changes}`"
    end

    wrap_in_transaction(repo, adapter, model, opts, embeds, [],
                        ~w(before_delete after_delete)a, fn ->
      changeset = Callbacks.__apply__(model, :before_delete, changeset)

      filters = add_pk_filter!(changeset.filters, struct)
      filters = Planner.fields(model, :delete, filters, adapter)

      case adapter.delete(repo, {prefix, source, model}, filters, autogen, opts) do
        {:ok, _} -> nil
        {:error, :stale} ->
          raise Ecto.StaleModelError, model: struct, action: :delete
      end

      changeset = put_in(changeset.model.__meta__.state, :deleted)
      {:ok, Callbacks.__apply__(model, :after_delete, changeset).model}
    end)
  end

  def delete(_repo, _adapter, %Changeset{valid?: false} = changeset, opts) when is_list(opts) do
    {:error, %{changeset | action: :delete}}
  end

  def delete(repo, adapter, %{__struct__: _} = struct, opts) when is_list(opts) do
    delete(repo, adapter, Ecto.Changeset.change(struct), opts)
  end

  ## Helpers

  defp struct_from_changeset!(action, %{action: given}) when given != nil and given != action,
    do: raise(ArgumentError, "a changeset with action #{inspect given} was given to Repo.#{action}")
  defp struct_from_changeset!(action, %{model: nil}),
    do: raise(ArgumentError, "cannot #{action} a changeset without a model")
  defp struct_from_changeset!(_action, %{model: struct}),
    do: struct

  defp load_changes(%{types: types} = changeset, values, adapter) do
    # It is ok to use types from changeset because we have
    # already filtered the results to be only about fields.
    model =
      changeset
      |> Ecto.Changeset.apply_changes
      |> do_load(values, types, adapter)

    model = put_in model.__meta__.state, :loaded
    Map.put(changeset, :model, model)
  end

  defp do_load(struct, kv, types, adapter) do
    Enum.reduce(kv, struct, fn
      {k, v}, acc ->
        type = Map.fetch!(types, k)
        case adapter.load(type, v) do
          {:ok, v} -> Map.put(acc, k, v)
          :error   -> raise ArgumentError, "cannot load `#{inspect v}` as type #{inspect type}"
        end
    end)
  end

  defp insert_changes(struct, fields, embeds, changeset) do
    types = changeset.types
    base =
      Enum.reduce embeds, Map.take(struct, fields), fn field, acc ->
        {:embed, embed} = Map.get(types, field)
        Map.put(acc, field, Ecto.Changeset.Relation.empty(embed))
      end
    update_in changeset.changes, &Map.merge(base, &1)
  end

  defp pop_from_changes(changeset, fields) do
    get_and_update_in(changeset.changes, &Map.split(&1, fields))
  end

  defp process_embeds(changeset, embeds, adapter, repo, opts) do
    {:ok, changeset} = process_children(changeset, embeds, adapter, repo, opts)
    changeset
  end

  defp process_assocs(changeset, embeds, adapter, repo, opts) do
    process_children(changeset, embeds, adapter, repo, opts)
  end

  defp process_children(changeset, related, _adapter, _repo, _opts) when related == %{} do
    {:ok, changeset}
  end

  defp process_children(changeset, related, adapter, repo, opts) do
    %Changeset{types: types, model: model, changes: changes, action: action} = changeset

    {model, changes, valid?} =
      Enum.reduce(related, {model, changes, true}, fn {field, changeset}, acc ->
        {_, related} = Map.get(types, field)
        process_children(related, field, changeset, adapter, repo, action, opts, acc)
      end)

    if valid? do
      {:ok, %{changeset | model: model}}
    else
      {:error, %{changeset | changes: changes}}
    end
  end

  defp process_children(%{cardinality: :one}, field, nil,
                        _adapter, _repo, _action, _opts, {parent, changes, valid?}) do
    {Map.put(parent, field, nil), Map.put(changes, field, nil), valid?}
  end

  defp process_children(%{cardinality: :one} = meta, field, changeset,
                        adapter, repo, action, opts, {parent, changes, valid?}) do
    case meta.__struct__.on_repo_action(meta, changeset, parent, adapter, repo, action, opts) do
      {:ok, model} ->
        {Map.put(parent, field, model), Map.put(changes, field, changeset), valid?}
      {:error, changeset} ->
        {parent, Map.put(changes, field, changeset), false}
    end
  end

  defp process_children(%{cardinality: :many} = meta, field, changesets,
                        adapter, repo, action, opts, {parent, changes, valid?}) do
    {changesets, {models, models_valid?}} =
      Enum.map_reduce(changesets, {[], true}, fn changeset, {models, models_valid?} ->
        case meta.__struct__.on_repo_action(meta, changeset, parent, adapter, repo, action, opts) do
          {:ok, nil} ->
            {changeset, {models, models_valid?}}
          {:ok, model} ->
            {changeset, {[model | models], models_valid?}}
          {:error, changeset} ->
            {changeset, {models, false}}
        end
      end)

    if models_valid? do
      {Map.put(parent, field, Enum.reverse(models)), Map.put(changes, field, changesets), valid?}
    else
      {parent, Map.put(changes, field, changesets), false}
    end
  end

  defp pop_autogenerate_id(changes, model) do
    case model.__schema__(:autogenerate_id) do
      {key, id} ->
        case Map.pop(changes, key) do
          {nil, changes} -> {{key, id, nil}, changes}
          {value, _}     -> {{key, id, value}, changes}
        end
      nil ->
        {nil, changes}
    end
  end

  defp get_autogenerate_id(changes, model) do
    case model.__schema__(:autogenerate_id) do
      {key, id} -> {key, id, Map.get(changes, key)}
      nil -> nil
    end
  end

  defp validate_changes(kind, changes, model, fields, adapter) do
    Planner.fields(model, kind, Map.take(changes, fields), adapter)
  end

  defp add_pk_filter!(filters, struct) do
    Enum.reduce Ecto.Model.primary_key!(struct), filters, fn
      {_k, nil}, _acc ->
        raise Ecto.NoPrimaryKeyValueError, struct: struct
      {k, v}, acc ->
        Map.put(acc, k, v)
    end
  end

  defp wrap_in_transaction(repo, adapter, model, opts, embeds, assocs, callbacks, fun) do
    if transaction_required?(model, embeds, assocs, callbacks) and
       function_exported?(adapter, :transaction, 3) do
      adapter.transaction(repo, opts, fn ->
        case fun.() do
          {:ok, model} -> model
          {:error, changeset} -> adapter.rollback(repo, changeset)
        end
      end)
    else
      fun.()
    end
  end

  defp transaction_required?(model, embeds, assocs, callbacks) do
    embeds != [] or assocs != [] or
      Enum.any?(callbacks, &function_exported?(model, &1, 1))
  end
end
