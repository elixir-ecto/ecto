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
    struct = struct_from_changeset!(:insert, changeset)
    model  = struct.__struct__
    fields = model.__schema__(:fields)
    embeds = model.__schema__(:embeds)
    assocs = model.__schema__(:associations)
    return = model.__schema__(:read_after_writes)

    # On insert, we always merge the whole struct into the
    # changeset as changes, except the primary key if it is nil.
    # We also remove all embeds that are not in the changes
    changeset = %{changeset | repo: repo, action: :insert}
    changeset = insert_changes(struct, fields, embeds, assocs, changeset)

    wrap_in_transaction(repo, adapter, model, opts, embeds, assocs,
                        ~w(before_insert after_insert)a, fn ->
      user_changeset = Callbacks.__apply__(model, :before_insert, changeset)

      changeset = Ecto.Embedded.prepare(user_changeset, embeds, adapter, :insert)
      {assoc_changes, changeset} = pop_from_changes(changeset, assocs)
      {autogen, changes} = pop_autogenerate_id(changeset.changes, model)
      changes = validate_changes(:insert, changes, model, fields, adapter)
      {embed_changes, changeset} = pop_from_changes(changeset, embeds)

      args = [repo, metadata(struct), changes, autogen, return, opts]
      case apply(changeset, adapter, :insert, args) do
        {:ok, changeset} ->
          opts = Keyword.put(opts, :skip_transaction, true)
          changeset
          |> process_embeds(embed_changes, adapter, repo, opts)
          |> process_assocs(assoc_changes, adapter, repo, opts)
          |> maybe_process_after(model, :after_insert)
        {:invalid, constraints} ->
          {:error, constraints_to_errors(user_changeset, :insert, constraints)}
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
    struct = struct_from_changeset!(:update, changeset)
    model  = struct.__struct__
    fields = model.__schema__(:fields)
    embeds = model.__schema__(:embeds)
    assocs = model.__schema__(:associations)
    return = model.__schema__(:read_after_writes)

    # Differently from insert, update does not copy the struct
    # fields into the changeset. All changes must be in the
    # changeset before hand.
    changeset = %{changeset | repo: repo, action: :update}

    if changeset.changes != %{} or opts[:force] do
      wrap_in_transaction(repo, adapter, model, opts, embeds, assocs,
                          ~w(before_update after_update)a, fn ->
        user_changeset = Callbacks.__apply__(model, :before_update, changeset)

        changeset = Ecto.Embedded.prepare(user_changeset, embeds, adapter, :update)
        {assoc_changes, changeset} = pop_from_changes(changeset, assocs)
        autogen = get_autogenerate_id(changeset.changes, model)
        changes = validate_changes(:update, changeset.changes, model, fields, adapter)
        {embed_changes, changeset} = pop_from_changes(changeset, embeds)

        filters = add_pk_filter!(changeset.filters, struct)
        filters = Planner.fields(model, :update, filters, adapter)

        args   = [repo, metadata(struct), changes, filters, autogen, return, opts]
        action = if changes == [], do: :noop, else: :update
        case apply(changeset, adapter, action, args) do
          {:ok, changeset} ->
            opts = Keyword.put(opts, :skip_transaction, true)
            changeset
            |> process_embeds(embed_changes, adapter, repo, opts)
            |> process_assocs(assoc_changes, adapter, repo, opts)
            |> maybe_process_after(model, :after_update)
          {:invalid, constraints} ->
            {:error, constraints_to_errors(user_changeset, :update, constraints)}
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
    embeds = model.__schema__(:embeds)

    changeset = %{changeset | repo: repo, action: :delete, changes: %{}}
    autogen   = get_autogenerate_id(changeset, model)

    wrap_in_transaction(repo, adapter, model, opts, embeds, [],
                        ~w(before_delete after_delete)a, fn ->
      changeset = Callbacks.__apply__(model, :before_delete, changeset)

      embeds  =
        changeset
        |> Ecto.Embedded.prepare(embeds, adapter, :delete)
        |> Map.fetch!(:changes)
        |> Map.take(embeds)

      filters = add_pk_filter!(changeset.filters, struct)
      filters = Planner.fields(model, :delete, filters, adapter)

      args = [repo, metadata(struct), filters, autogen, opts]
      case apply(changeset, adapter, :delete, args) do
        {:ok, changeset} ->
          opts = Keyword.put(opts, :skip_transaction, true)
          # We ignore the results because we still want to keep
          # the embed values in the model. Also note we don't
          # process associations because they are handled externally.
          _ = process_embeds(changeset, embeds, adapter, repo, opts)
          {:ok, Callbacks.__apply__(model, :after_delete, changeset).model}
        {:invalid, constraints} ->
          {:error, constraints_to_errors(changeset, :delete, constraints)}
      end
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

  defp metadata(%{__struct__: model, __meta__: meta}) do
    meta
    |> Map.delete(:__struct__)
    |> Map.put(:model, model)
  end

  defp apply(changeset, _adapter, :noop, _args) do
    {:ok, changeset}
  end

  defp apply(changeset, adapter, action, args) do
    case apply(adapter, action, args) do
      {:ok, values} ->
        {:ok, load_changes(changeset, action, values, adapter)}
      {:invalid, _} = constraints ->
        constraints
      {:error, :stale} ->
        raise Ecto.StaleModelError, model: changeset.model, action: action
    end
  end

  defp constraints_to_errors(%{constraints: user_constraints} = changeset, action, constraints) do
    Enum.reduce constraints, changeset, fn {type, constraint}, acc ->
      user_constraint =
        Enum.find(user_constraints, fn c ->
          c.type == type and c.constraint == constraint
        end)

      case user_constraint do
        %{field: field, message: message} ->
          Ecto.Changeset.add_error(acc, field, message)
        nil ->
          raise Ecto.ConstraintError, action: action, type: type,
                                      constraint: constraint, changeset: changeset
      end
    end
  end

  defp load_changes(%{types: types} = changeset, action, values, adapter) do
    # It is ok to use types from changeset because we have
    # already filtered the results to be only about fields.
    model =
      changeset
      |> Ecto.Changeset.apply_changes
      |> do_load(values, types, adapter)
    model = put_in(model.__meta__.state, action_to_state(action))
    Map.put(changeset, :model, model)
  end

  defp action_to_state(:insert), do: :loaded
  defp action_to_state(:update), do: :loaded
  defp action_to_state(:delete), do: :deleted

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

  defp insert_changes(struct, fields, embeds, assocs, changeset) do
    types = changeset.types
    assert_empty_relation!(struct, embeds, types)
    assert_empty_relation!(struct, assocs, types)

    base =
      Enum.reduce embeds, Map.take(struct, fields), fn field, acc ->
        {:embed, embed} = Map.get(types, field)
        Map.put(acc, field, Ecto.Changeset.Relation.empty(embed))
      end

    update_in changeset.changes, &Map.merge(base, &1)
  end

  defp assert_empty_relation!(struct, relation, types) do
    Enum.each relation, fn field ->
      case Map.get(types, field) do
        {kind, relation} ->
          value = Map.get(struct, field)
          unless Ecto.Changeset.Relation.empty?(relation, value) do
            raise ArgumentError, "model #{inspect struct.__struct__} has value `#{inspect value}` " <>
              "set for #{kind} named `#{field}`. #{kind}s can only be manipulate via changesets, " <>
              "be it on insert, update or delete."
          end
        _ ->
          :ok
      end
    end
  end

  defp pop_from_changes(changeset, fields) do
    get_and_update_in(changeset.changes, &Map.split(&1, fields))
  end

  defp process_embeds(changeset, embeds, adapter, repo, opts) do
    {:ok, changeset} =
      Ecto.Changeset.Relation.on_repo_action(changeset, embeds, adapter, repo, opts)
    changeset
  end

  defp process_assocs(changeset, assocs, adapter, repo, opts) do
    Ecto.Changeset.Relation.on_repo_action(changeset, assocs, adapter, repo, opts)
  end

  defp maybe_process_after({:ok, changeset}, model, callback) do
    {:ok, Callbacks.__apply__(model, callback, changeset).model}
  end

  defp maybe_process_after({:error, changeset}, _model, _callback) do
    {:error, %{changeset | valid?: false}}
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
       Keyword.get(opts, :skip_transaction) != true and
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
