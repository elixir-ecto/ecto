defmodule Ecto.Repo.Model do
  # The module invoked by user defined repos
  # for model related functionality.
  @moduledoc false

  alias Ecto.Query.Planner
  alias Ecto.Model.Callbacks
  alias Ecto.Changeset

  @doc """
  Implementation for `Ecto.Repo.insert/2`.
  """
  def insert(repo, adapter, %Changeset{} = changeset, opts) when is_list(opts) do
    struct = struct_from_changeset!(changeset)
    model  = struct.__struct__
    fields = model.__schema__(:fields)
    source = struct.__meta__.source
    return = model.__schema__(:read_after_writes)

    # On insert, we always merge the whole struct into the
    # changeset as changes, except the primary key if it is nil.
    changeset = %{changeset | repo: repo}
    changeset = merge_into_changeset(model, struct, fields, changeset)

    with_transactions_if_callbacks repo, adapter, model, opts,
                                   ~w(before_insert after_insert)a, fn ->
      # Callbacks.__apply__/3 "ignores" undefined callbacks and simply returns
      # the changeset unchanged in case the callback is missing.
      changeset = Callbacks.__apply__(model, :before_insert, changeset)
      changes   = validate_changes(:insert, model, fields, changeset)

      {:ok, values} = adapter.insert(repo, source, changes, return, opts)

      changeset = load_into_changeset(changeset, model, values)
      Callbacks.__apply__(model, :after_insert, changeset).model
    end
  end

  def insert(repo, adapter, %{__struct__: _} = struct, opts) do
    insert(repo, adapter, %Changeset{model: struct, valid?: true}, opts)
  end

  @doc """
  Implementation for `Ecto.Repo.update/2`.
  """
  def update(repo, adapter, %Changeset{} = changeset, opts) when is_list(opts) do
    struct = struct_from_changeset!(changeset)
    model  = struct.__struct__
    fields = model.__schema__(:fields)
    source = struct.__meta__.source
    return = model.__schema__(:read_after_writes)

    # Differently from insert, update does not copy the struct
    # fields into the changeset. All changes must be in the
    # changeset before hand.
    changeset = %{changeset | repo: repo}

    with_transactions_if_callbacks repo, adapter, model, opts,
                                   ~w(before_update after_update)a, fn ->
      # Callbacks.__apply__/3 "ignores" undefined callbacks and simply returns
      # the changeset unchanged in case the callback is missing.
      changeset = Callbacks.__apply__(model, :before_update, changeset)
      changes   = validate_changes(:update, model, fields, changeset)

      {pk_field, pk_value} = pk_filter!(model, struct)
      filters = Planner.fields(:update, model, Map.put(changeset.filters, pk_field, pk_value))

      values =
        if changes != [] do
          case adapter.update(repo, source, changes, filters, return, opts) do
            {:ok, values} ->
              values
            {:error, :stale} ->
              raise Ecto.StaleModelError, model: struct, action: :update
          end
        else
          []
        end

      changeset = load_into_changeset(changeset, model, values)
      Callbacks.__apply__(model, :after_update, changeset).model
    end
  end

  def update(repo, adapter, %{__struct__: model} = struct, opts) do
    changes = Map.take(struct, model.__schema__(:fields))

    # If we have a primary key field, we should
    # not include it in the list of changes.
    if pk_field = model.__schema__(:primary_key) do
      changes = Map.delete(changes, pk_field)
    end

    changeset = %Changeset{model: struct, valid?: true, changes: changes}
    update(repo, adapter, changeset, opts)
  end

  @doc """
  Implementation for `Ecto.Repo.delete/2`.
  """
  def delete(repo, adapter, %Changeset{} = changeset, opts) when is_list(opts) do
    struct = struct_from_changeset!(changeset)
    model  = struct.__struct__
    source = struct.__meta__.source

    # There are no field changes on delete
    changeset = %{changeset | repo: repo}

    with_transactions_if_callbacks repo, adapter, model, opts,
                                   ~w(before_delete after_delete)a, fn ->
      changeset = Callbacks.__apply__(model, :before_delete, changeset)

      {pk_field, pk_value} = pk_filter!(model, struct)
      filters = Planner.fields(:delete, model, Map.put(changeset.filters, pk_field, pk_value))

      case adapter.delete(repo, source, filters, opts) do
        {:ok, _} -> nil
        {:error, :stale} ->
          raise Ecto.StaleModelError, model: struct, action: :delete
      end

      model = Callbacks.__apply__(model, :after_delete, changeset).model
      put_in model.__meta__.state, :deleted
    end
  end

  def delete(repo, adapter, %{__struct__: _} = struct, opts) do
    delete(repo, adapter, %Changeset{model: struct, valid?: true}, opts)
  end

  ## Helpers

  defp struct_from_changeset!(%{valid?: false}),
    do: raise(ArgumentError, "cannot insert/update an invalid changeset")
  defp struct_from_changeset!(%{model: nil}),
    do: raise(ArgumentError, "cannot insert/update a changeset without a model")
  defp struct_from_changeset!(%{model: struct}),
    do: struct

  defp load_into_changeset(%{changes: changes} = changeset, model, values) do
    update_in changeset.model, &do_load(struct(&1, changes), model, values)
  end

  defp do_load(struct, model, kv) do
    types = model.__changeset__

    model = Enum.reduce(kv, struct, fn
      {k,v}, acc ->
        value = Ecto.Type.load!(Map.fetch!(types, k), v)
        Map.put(acc, k, value)
    end)

    put_in model.__meta__.state, :loaded
  end

  defp merge_into_changeset(model, struct, fields, changeset) do
    changes  = Map.take(struct, fields)
    pk_field = model.__schema__(:primary_key)

    # If we have a primary key field but it is nil,
    # we should not include it in the list of changes.
    if pk_field && !Ecto.Model.primary_key(struct)[pk_field] do
      changes = Map.delete(changes, pk_field)
    end

    update_in changeset.changes, &Map.merge(changes, &1)
  end

  defp validate_changes(kind, model, fields, changeset) do
    Planner.fields(kind, model, Map.take(changeset.changes, fields))
  end

  defp pk_filter!(model, struct) do
    [{pk_field, pk_value}] = Ecto.Model.primary_key(struct)
    pk_value || raise Ecto.MissingPrimaryKeyError, struct: struct
    {pk_field, pk_value}
  end

  defp with_transactions_if_callbacks(repo, adapter, model, opts, callbacks, fun) do
    if Enum.any?(callbacks, &function_exported?(model, &1, 1)) do
      {:ok, value} = adapter.transaction(repo, opts, fun)
      value
    else
      fun.()
    end
  end
end
