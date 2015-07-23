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
    {prefix, source} = struct.__meta__.source
    return   = model.__schema__(:read_after_writes)

    # On insert, we always merge the whole struct into the
    # changeset as changes, except the primary key if it is nil.
    # We also remove all embeds that are not in the changes
    changeset = %{changeset | repo: repo, action: :insert}
    changeset = insert_changes(struct, fields, embeds, changeset)

    with_transactions_if_callbacks repo, adapter, model, opts, embeds,
                                   ~w(before_insert after_insert)a, fn ->
      changeset = Callbacks.__apply__(model, :before_insert, changeset)
      changeset = Ecto.Embedded.apply_callbacks(changeset, embeds, adapter, :insert, :before)

      {autogen, changes} = pop_autogenerate_id(changeset.changes, model)
      changes = validate_changes(:insert, changes, model, fields, adapter)

      {:ok, values} = adapter.insert(repo, {prefix, source, model}, changes, autogen, return, opts)

      # Embeds can't be `read_after_writes` so we don't care
      # about values returned from the adapter
      changeset = Ecto.Embedded.apply_callbacks(changeset, embeds, adapter, :insert, :after)
      changeset = load_changes(changeset, values, adapter)
      {:ok, Callbacks.__apply__(model, :after_insert, changeset).model}
    end
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
    {prefix, source} = struct.__meta__.source
    return   = model.__schema__(:read_after_writes)

    # Differently from insert, update does not copy the struct
    # fields into the changeset. All changes must be in the
    # changeset before hand.
    changeset = %{changeset | repo: repo, action: :update}

    if changeset.changes != %{} or opts[:force] do
      with_transactions_if_callbacks repo, adapter, model, opts, embeds,
                                     ~w(before_update after_update)a, fn ->
        changeset = Callbacks.__apply__(model, :before_update, changeset)
        changeset = Ecto.Embedded.apply_callbacks(changeset, embeds, adapter, :update, :before)

        autogen = get_autogenerate_id(changeset.changes, model)
        changes = validate_changes(:update, changeset.changes, model, fields, adapter)

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

        # As in inserts, embeds can't be `read_after_writes` so we don't care
        # about values returned from the adapter
        changeset = Ecto.Embedded.apply_callbacks(changeset, embeds, adapter, :update, :after)
        changeset = load_changes(changeset, values, adapter)
        {:ok, Callbacks.__apply__(model, :after_update, changeset).model}
      end
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

    # We mark all embeds for deletion, and ignore other changes in changeset
    changeset = %{changeset | repo: repo, action: :delete}
    changeset = delete_changes(changeset, model)
    autogen   = get_autogenerate_id(changeset, model)

    with_transactions_if_callbacks repo, adapter, model, opts, embeds,
                                   ~w(before_delete after_delete)a, fn ->
      changeset = Callbacks.__apply__(model, :before_delete, changeset)
      changeset = Ecto.Embedded.apply_callbacks(changeset, embeds, adapter, :delete, :before)

      filters = add_pk_filter!(changeset.filters, struct)
      filters = Planner.fields(model, :delete, filters, adapter)

      case adapter.delete(repo, {prefix, source, model}, filters, autogen, opts) do
        {:ok, _} -> nil
        {:error, :stale} ->
          raise Ecto.StaleModelError, model: struct, action: :delete
      end

      # We load_changes as we need to remove all embeds
      changeset = Ecto.Embedded.apply_callbacks(changeset, embeds, adapter, :delete, :after)
      changeset = load_changes(changeset, [], adapter)
      model = Callbacks.__apply__(model, :after_delete, changeset).model
      {:ok, put_in(model.__meta__.state, :deleted)}
    end
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

    Map.put(changeset, :model, model)
  end

  defp do_load(struct, kv, types, adapter) do
    model = Enum.reduce(kv, struct, fn
      {k, v}, acc ->
        type = Map.fetch!(types, k)
        case adapter.load(type, v) do
          {:ok, v} -> Map.put(acc, k, v)
          :error   -> raise ArgumentError, "cannot load `#{inspect v}` as type #{inspect type}"
        end
    end)

    put_in model.__meta__.state, :loaded
  end

  defp delete_changes(changeset, model) do
    types = changeset.types
    embeds =
      Enum.map(model.__schema__(:embeds), fn field ->
        {:embed, embed} = Map.get(types, field)
        {field, Ecto.Embedded.empty(embed)}
      end)

    changeset = %{changeset | changes: %{}}
    Ecto.Changeset.change(changeset, embeds)
  end

  defp insert_changes(struct, fields, embeds, changeset) do
    types = changeset.types

    base  =
      Enum.reduce embeds, Map.take(struct, fields), fn field, acc ->
        {:embed, embed} = Map.get(types, field)
        Map.put(acc, field, Ecto.Embedded.empty(embed))
      end

    update_in changeset.changes, &Map.merge(base, &1)
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
        raise Ecto.MissingPrimaryKeyError, struct: struct
      {k, v}, acc ->
        Map.put(acc, k, v)
    end
  end

  defp with_transactions_if_callbacks(repo, adapter, model, opts, embeds, callbacks, fun) do
    if (embeds != [] or Enum.any?(callbacks, &function_exported?(model, &1, 1))) and
       function_exported?(adapter, :transaction, 3) do
      {:ok, value} = adapter.transaction(repo, opts, fun)
      value
    else
      fun.()
    end
  end
end
