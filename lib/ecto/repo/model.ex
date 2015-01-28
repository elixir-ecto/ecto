defmodule Ecto.Repo.Model do
  # The module invoked by user defined repos
  # for model related functionality.
  @moduledoc false

  alias Ecto.Query.Planner
  alias Ecto.Model.Callbacks

  @doc """
  Implementation for `Ecto.Repo.insert/2`.
  """
  def insert(repo, adapter, %Ecto.Changeset{} = changeset, opts) when is_list(opts) do
    struct = struct_from_changeset!(changeset)
    model  = struct.__struct__
    fields = model.__schema__(:fields)
    source = model.__schema__(:source)
    return = handle_returning(adapter, model)

    # On insert, we always merge the whole struct into the
    # changeset as changes, except the primary key if it is nil.
    changeset = %{changeset | repo: repo}
    changeset = merge_into_changeset(model, struct, fields, changeset)

    with_transactions_if_callbacks repo, adapter, model, opts,
                                   ~w(before_insert after_insert)a, fn ->
      changeset = Callbacks.__apply__(model, :before_insert, changeset)
      changes   = validate_changes(:insert, model, fields, changeset)

      {:ok, values} = adapter.insert(repo, source, changes, return, opts)

      changeset = load_into_changeset(changeset, model, return, values)
      Callbacks.__apply__(model, :after_insert, changeset).model
    end
  end

  def insert(repo, adapter, %{__struct__: _} = struct, opts) do
    insert(repo, adapter, %Ecto.Changeset{model: struct, valid?: true}, opts)
  end

  @doc """
  Implementation for `Ecto.Repo.update/2`.
  """
  def update(repo, adapter, %Ecto.Changeset{} = changeset, opts) when is_list(opts) do
    struct = struct_from_changeset!(changeset)
    model  = struct.__struct__
    fields = model.__schema__(:fields)
    source = model.__schema__(:source)
    return = handle_returning(adapter, model)

    # Differently from insert, update does not copy the struct
    # fields into the changeset. All changes must be in the
    # changeset before hand.
    changeset = %{changeset | repo: repo}

    with_transactions_if_callbacks repo, adapter, model, opts,
                                   ~w(before_update after_update)a, fn ->
      changeset = Callbacks.__apply__(model, :before_update, changeset)
      changes   = validate_changes(:update, model, fields, changeset)

      pk_filter = Planner.fields(:update, model, pk_filter(model, struct))

      if changes == [] do
        changes = pk_filter
      end

      {:ok, values} = adapter.update(repo, source, pk_filter, changes, return, opts)

      changeset = load_into_changeset(changeset, model, return, values)
      Callbacks.__apply__(model, :after_update, changeset).model
    end
  end

  def update(repo, adapter, %{__struct__: model} = struct, opts) do
    changes   = Map.take(struct, model.__schema__(:fields))
    changeset = %Ecto.Changeset{model: struct, valid?: true, changes: changes}
    update(repo, adapter, changeset, opts)
  end

  @doc """
  Implementation for `Ecto.Repo.delete/2`.
  """
  def delete(repo, adapter, %Ecto.Changeset{} = changeset, opts) when is_list(opts) do
    struct = struct_from_changeset!(changeset)
    model  = struct.__struct__
    source = model.__schema__(:source)

    # There are no field changes on delete
    changeset = %{changeset | repo: repo}

    with_transactions_if_callbacks repo, adapter, model, opts,
                                   ~w(before_delete after_delete)a, fn ->
      changeset = Callbacks.__apply__(model, :before_delete, changeset)

      pk_filter = Planner.fields(:delete, model, pk_filter(model, struct))
      {:ok, _} = adapter.delete(repo, source, pk_filter, opts)

      Callbacks.__apply__(model, :after_delete, changeset).model
      |> Map.put(:__state__, :deleted)
    end
  end

  def delete(repo, adapter, %{__struct__: _} = struct, opts) do
    delete(repo, adapter, %Ecto.Changeset{model: struct, valid?: true}, opts)
  end

  ## Helpers

  def handle_returning(Ecto.Adapters.MySQL, _model), 
    do: []
  def handle_returning(_adapter, model), 
    do: model.__schema__(:read_after_writes)

  defp struct_from_changeset!(%{valid?: false}),
    do: raise(ArgumentError, "cannot insert/update an invalid changeset")
  defp struct_from_changeset!(%{model: nil}),
    do: raise(ArgumentError, "cannot insert/update a changeset without a model")
  defp struct_from_changeset!(%{model: struct}),
    do: struct

  defp load_into_changeset(%{changes: changes} = changeset, model, return, values) do
    update_in changeset.model,
              &model.__schema__(:load, struct(&1, changes), return, values)
  end

  defp merge_into_changeset(model, struct, fields, changeset) do
    changes  = Map.take(struct, fields)
    pk_field = model.__schema__(:primary_key)

    # If we have a primary key field but it is nil,
    # we should not include it in the list of changes.
    if pk_field && !Ecto.Model.primary_key(struct) do
      changes = Map.delete(changes, pk_field)
    end

    update_in changeset.changes, &Map.merge(changes, &1)
  end

  defp validate_changes(kind, model, fields, changeset) do
    Planner.fields(kind, model, Map.take(changeset.changes, fields))
  end

  defp pk_filter(model, struct) do
    pk_field = model.__schema__(:primary_key)
    pk_value = Ecto.Model.primary_key(struct) ||
                 raise Ecto.MissingPrimaryKeyError, struct: struct
    [{pk_field, pk_value}]
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
