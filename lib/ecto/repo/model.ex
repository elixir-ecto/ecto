defmodule Ecto.Repo.Model do
  # The module invoked by user defined repos
  # for model related functionality.
  @moduledoc false

  alias Ecto.Query.Planner
  alias Ecto.Model.Callbacks
  alias Ecto.Changeset

  def insert(repo, adapter, model_or_changeset, opts) do
    IO.puts :stderr, "[warning] Repo.insert/2 is deprecated, please use Repo.insert!/2 instead\n" <>
                     Exception.format_stacktrace()
    insert!(repo, adapter, model_or_changeset, opts)
  end

  def update(repo, adapter, model_or_changeset, opts) do
    IO.puts :stderr, "[warning] Repo.update/2 is deprecated, please use Repo.update!/2 instead\n" <>
                     Exception.format_stacktrace()
    update!(repo, adapter, model_or_changeset, opts)
  end

  def delete(repo, adapter, model_or_changeset, opts) do
    IO.puts :stderr, "[warning] Repo.delete/2 is deprecated, please use Repo.delete!/2 instead\n" <>
                     Exception.format_stacktrace()
    delete!(repo, adapter, model_or_changeset, opts)
  end

  @doc """
  Implementation for `Ecto.Repo.insert!/2`.
  """
  def insert!(repo, adapter, %Changeset{} = changeset, opts) when is_list(opts) do
    struct   = struct_from_changeset!(changeset)
    model    = struct.__struct__
    fields   = model.__schema__(:fields)
    embeds   = model.__schema__(:embeds)
    {prefix, source} = struct.__meta__.source
    return   = model.__schema__(:read_after_writes)
    id_types = adapter.id_types(repo)

    # On insert, we always merge the whole struct into the
    changeset = %{changeset | repo: repo, action: :insert}
    changeset = merge_into_changeset(struct, fields, embeds, changeset)

    changeset = merge_autogenerate(changeset, model)
    {autogen, changeset} = merge_autogenerate_id(changeset, model)

    with_transactions_if_callbacks repo, adapter, model, opts,
                                   ~w(before_insert after_insert)a, fn ->
      changeset = apply_embedded_callbacks(embeds, changeset, :before_insert)
      changeset = Callbacks.__apply__(model, :before_insert, changeset)
      changes = validate_changes(:insert, changeset, model, fields, id_types)

      {:ok, values} = adapter.insert(repo, {prefix, source, model}, changes, autogen, return, opts)

      changeset = load_into_changeset(changeset, values, id_types)
      Callbacks.__apply__(model, :after_insert, changeset).model
    end
  end

  def insert!(repo, adapter, %{__struct__: _} = struct, opts) when is_list(opts) do
    insert!(repo, adapter, Ecto.Changeset.change(struct), opts)
  end

  @doc """
  Implementation for `Ecto.Repo.update!/2`.
  """
  def update!(repo, adapter, %Changeset{} = changeset, opts) when is_list(opts) do
    struct   = struct_from_changeset!(changeset)
    model    = struct.__struct__
    fields   = model.__schema__(:fields)
    {prefix, source} = struct.__meta__.source
    return   = model.__schema__(:read_after_writes)
    id_types = adapter.id_types(repo)

    # Differently from insert, update does not copy the struct
    # fields into the changeset. All changes must be in the
    # changeset before hand.
    changeset = %{changeset | repo: repo, action: :update}
    autogen   = get_autogenerate_id(changeset, model)

    if changeset.changes != %{} or opts[:force] do
      with_transactions_if_callbacks repo, adapter, model, opts,
                                     ~w(before_update after_update)a, fn ->
        changeset = Callbacks.__apply__(model, :before_update, changeset)
        changes   = validate_changes(:update, changeset, model, fields, id_types)

        filters = add_pk_filter!(changeset.filters, struct)
        filters = Planner.fields(model, :update, filters, id_types)

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

        changeset = load_into_changeset(changeset, values, id_types)
        Callbacks.__apply__(model, :after_update, changeset).model
      end
    else
      changeset.model
    end
  end

  def update!(repo, adapter, %{__struct__: model} = struct, opts) when is_list(opts) do
    changes = Map.take(struct, model.__schema__(:fields))

    # Remove all primary key fields from the list of changes.
    changes =
      struct
      |> Map.take(model.__schema__(:fields))
      |> Map.drop(model.__schema__(:primary_key))
      |> Map.drop(model.__schema__(:embeds))

    changeset = %{Ecto.Changeset.change(struct) | changes: changes}
    update!(repo, adapter, changeset, opts)
  end

  @doc """
  Implementation for `Ecto.Repo.delete!/2`.
  """
  def delete!(repo, adapter, %Changeset{} = changeset, opts) when is_list(opts) do
    struct = struct_from_changeset!(changeset)
    model  = struct.__struct__
    {prefix, source} = struct.__meta__.source

    # There are no field changes on delete
    changeset = %{changeset | repo: repo, action: :delete}
    autogen   = get_autogenerate_id(changeset, model)

    with_transactions_if_callbacks repo, adapter, model, opts,
                                   ~w(before_delete after_delete)a, fn ->
      changeset = Callbacks.__apply__(model, :before_delete, changeset)

      filters = add_pk_filter!(changeset.filters, struct)
      filters = Planner.fields(model, :delete, filters, adapter.id_types(repo))

      case adapter.delete(repo, {prefix, source, model}, filters, autogen, opts) do
        {:ok, _} -> nil
        {:error, :stale} ->
          raise Ecto.StaleModelError, model: struct, action: :delete
      end

      model = Callbacks.__apply__(model, :after_delete, changeset).model
      put_in model.__meta__.state, :deleted
    end
  end

  def delete!(repo, adapter, %{__struct__: _} = struct, opts) when is_list(opts) do
    delete!(repo, adapter, Ecto.Changeset.change(struct), opts)
  end

  ## Helpers

  defp struct_from_changeset!(%{valid?: false}),
    do: raise(ArgumentError, "cannot insert/update an invalid changeset")
  defp struct_from_changeset!(%{model: nil}),
    do: raise(ArgumentError, "cannot insert/update a changeset without a model")
  defp struct_from_changeset!(%{model: struct}),
    do: struct

  defp load_into_changeset(%{changes: changes, types: types} = changeset, values, id_types) do
    # It is ok to use types from changeset because
    # we have already filtered the results
    # to be only about fields.
    update_in changeset.model, &do_load(struct(&1, changes), values, types, id_types)
  end

  defp do_load(struct, kv, types, id_types) do
    model = Enum.reduce(kv, struct, fn
      {k, v}, acc ->
        value =
          types
          |> Map.fetch!(k)
          |> Ecto.Type.load!(v, id_types)
        Map.put(acc, k, value)
    end)

    put_in model.__meta__.state, :loaded
  end

  defp merge_into_changeset(struct, fields, embeds, changeset) do
    changes =
      struct
      |> Map.take(fields)
      |> Map.drop(embeds)

    update_in changeset.changes, &Map.merge(changes, &1)
  end

  defp apply_embedded_callbacks(embeds, changeset, callback) do
    types = changeset.types

    update_in changeset.changes, fn changes ->
      Enum.reduce(embeds, changes, fn name, changes ->
        case Map.fetch(changes, name) do
          {:ok, changeset} ->
            {:embed, embed} = Map.get(types, name)
            Map.put(changes, name, Ecto.Embedded.apply_callback(embed, changeset, callback))
          :error ->
            changes
        end
      end)
    end
  end


  defp merge_autogenerate_id(changeset, model) do
    case model.__schema__(:autogenerate_id) do
      {key, id} ->
        get_and_update_in changeset.changes, fn changes ->
          case Map.pop(changes, key) do
            {nil, changes} -> {{key, id, nil}, changes}
            {value, _}     -> {{key, id, value}, changes}
          end
        end
      nil ->
        {nil, changeset}
    end
  end

  defp get_autogenerate_id(changeset, model) do
    case model.__schema__(:autogenerate_id) do
      {key, id} -> {key, id, Map.get(changeset.changes, key)}
      nil -> nil
    end
  end

  defp merge_autogenerate(changeset, model) do
    update_in changeset.changes, fn changes ->
      Enum.reduce model.__schema__(:autogenerate), changes, fn {k, v}, acc ->
        if Map.get(acc, k) == nil do
          Map.put(acc, k, v.generate())
        else
          acc
        end
      end
    end
  end

  defp validate_changes(kind, changeset, model, fields, id_types) do
    Planner.fields(model, kind, Map.take(changeset.changes, fields), id_types)
  end

  defp add_pk_filter!(filters, struct) do
    Enum.reduce Ecto.Model.primary_key!(struct), filters, fn
      {_k, nil}, _acc ->
        raise Ecto.MissingPrimaryKeyError, struct: struct
      {k, v}, acc ->
        Map.put(acc, k, v)
    end
  end

  defp with_transactions_if_callbacks(repo, adapter, model, opts, callbacks, fun) do
    # TODO how should that work with embeds
    if Enum.any?(callbacks, &function_exported?(model, &1, 1)) and
       function_exported?(adapter, :transaction, 3) do
      {:ok, value} = adapter.transaction(repo, opts, fun)
      value
    else
      fun.()
    end
  end
end
