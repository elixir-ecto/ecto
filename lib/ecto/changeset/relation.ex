defmodule Ecto.Changeset.Relation do
  @moduledoc false

  alias Ecto.Changeset

  @doc """
  Returns empty container for relation.

  Handles both the relation structs as well as Ecto.Association.NotLoaded.
  """
  def empty(%{cardinality: cardinality}), do: empty(cardinality)
  def empty(%{__cardinality__: cardinality}), do: empty(cardinality)

  def empty(:one), do: nil
  def empty(:many), do: []

  @doc """
  Casts embedded models according to the `on_cast` function.

  Sets correct `state` on the returned changeset
  """
  def cast(relation, model, params, current) do
    cast(relation, params, loaded_or_empty!(model, current))
  end

  defp cast(%{cardinality: :one, related: mod, on_cast: fun}, :empty, current) do
    {:ok, current && do_cast(mod, fun, :empty, current), false, false}
  end

  defp cast(%{cardinality: :many, related: mod, on_cast: fun}, :empty, current) do
    {:ok, Enum.map(current, &do_cast(mod, fun, :empty, &1)), false, false}
  end

  defp cast(%{cardinality: :one}, nil, _current) do
    {:ok, nil, false, false}
  end

  defp cast(%{cardinality: :many} = related, params, current) when is_map(params) do
    params =
      params
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))
    cast(related, params, current)
  end

  defp cast(%{related: mod, on_cast: fun} = related, params, current) do
    {pks, param_pks} = primary_keys(mod)
    cast_or_change(related, params, current, param_pks, pks, &do_cast(mod, fun, &1, &2))
  end

  defp do_cast(mod, fun, params, nil) do
    apply(mod, fun, [mod.__struct__(), params]) |> put_new_action(:insert)
  end

  defp do_cast(_mod, _fun, nil, model) do
    Changeset.change(model) |> put_new_action(:delete)
  end

  defp do_cast(mod, fun, params, model) do
    apply(mod, fun, [model, params]) |> put_new_action(:update)
  end

  @doc """
  Wraps embedded models in changesets.
  """
  def change(_related, _model, nil, nil), do: {:ok, nil, false, true}

  def change(%{related: mod} = related, model, value, current) do
    current = loaded_or_empty!(model, current)
    {pks, _} = primary_keys(mod)
    cast_or_change(related, value, current, pks, pks, &do_change(&1, &2, mod))
  end

  defp do_change(value, nil, mod) do
    fields    = mod.__schema__(:fields)
    embeds    = mod.__schema__(:embeds)
    assocs    = mod.__schema__(:associations)
    changeset = Changeset.change(value)
    model     = changeset.model
    types     = changeset.types

    changes =
      Enum.reduce(embeds, Map.take(model, fields), fn field, acc ->
        {:embed, embed} = Map.get(types, field)
        case change(embed, model, Map.get(acc, field), nil) do
          {:ok, _, _, true}       -> acc
          {:ok, change, _, false} -> Map.put(acc, field, change)
        end
      end)

    changes =
      Enum.reduce(assocs, changes, fn field, acc ->
        # We use fetch to filter has through and belongs_to associations,
        # as they are not in the changeset types
        case Map.fetch(types, field) do
          {:ok, {:assoc, assoc}} ->
            value = loaded_or_empty!(model, Map.get(model, field))
            case change(assoc, model, value, nil) do
              {:ok, _, _, true}       -> acc
              {:ok, change, _, false} -> Map.put(acc, field, change)
            end
          :error ->
            acc
        end
      end)

    update_in(changeset.changes, &Map.merge(changes, &1)) |> put_new_action(:insert)
  end

  defp do_change(nil, current, mod) do
    # We need to mark all embeds for deletion too
    changes =
      Enum.map(mod.__schema__(:embeds), fn field ->
        {field, Changeset.Relation.empty(mod.__schema__(:embed, field))}
      end)

    Changeset.change(current, changes) |> put_new_action(:delete)
  end

  defp do_change(%Changeset{model: current} = changeset, current, _mod) do
    changeset |> put_new_action(:update)
  end

  defp do_change(%Changeset{}, _current, _mod) do
    raise ArgumentError, "embedded changeset has a different model than the one specified in the schema"
  end

  defp do_change(value, current, _mod) do
    changes = Map.take(value, value.__struct__.__schema__(:fields))
    Changeset.change(current, changes) |> put_new_action(:update)
  end

  defp cast_or_change(%{cardinality: :one}, value, current, param_pks, pks, fun) when is_map(value) or is_nil(value) do
    single_change(value, pks, param_pks, fun, current)
  end

  defp cast_or_change(%{cardinality: :many}, value, current, param_pks, pks, fun) when is_list(value) do
    map_changes(value, pks, param_pks, fun, current)
  end

  defp cast_or_change(_, _, _, _, _, _), do: :error

  defp map_changes(list, pks, param_pks, fun, current) do
    map_changes(list, param_pks, fun, process_current(current, pks), [], true, true)
  end

  defp map_changes([], _pks, fun, current, acc, valid?, skip?) do
    {previous, {valid?, skip?}} =
      Enum.map_reduce(current, {valid?, skip?}, fn {_, model}, {valid?, skip?} ->
        changeset = fun.(nil, model)
        {changeset, {valid? && changeset.valid?, skip? && skip?(changeset)}}
      end)

    {:ok, Enum.reverse(acc, previous), valid?, skip?}
  end

  defp map_changes([map | rest], pks, fun, current, acc, valid?, skip?) when is_map(map) do
    pk_values = get_pks(map, pks)
    {model, current} =
      case Map.fetch(current, pk_values) do
        {:ok, model} ->
          {model, Map.delete(current, pk_values)}
        :error ->
          if Enum.all?(pk_values, &is_nil/1) do
            {nil, current}
          else
            raise Ecto.UnmachedRelationError, new_value: map, old_value: Map.values(current), cardinality: :many
          end
      end

    changeset = fun.(map, model)
    map_changes(rest, pks, fun, current, [changeset | acc],
                valid? && changeset.valid?, skip? && skip?(changeset))
  end

  defp map_changes(_params, _pkd, _fun, _current, _acc, _valid?, _skip?) do
    :error
  end

  defp single_change(new, current_pks, new_pks, fun, current) do
    current = current_or_nil(new, new_pks, current, current_pks)

    changeset = fun.(new, current)
    {:ok, changeset, changeset.valid?, skip?(changeset)}
  end

  defp current_or_nil(nil, _new_pks, current, _current_pks), do: current
  defp current_or_nil(_new, _new_pks, nil, _current_pks), do: nil
  defp current_or_nil(new, new_pks, current, current_pks) do
    new_pk_values = get_pks(new, new_pks)
    current_pk_values = get_pks(current, current_pks)

    cond do
      new_pk_values == current_pk_values ->
        current
      Enum.all?(new_pk_values, &is_nil/1) ->
        nil
      true ->
        raise Ecto.UnmachedRelationError, new_value: new, old_value: current, cardinality: :one
    end
  end

  defp get_pks(%Changeset{model: model}, pks),
    do: get_pks(model, pks)
  defp get_pks(model_or_params, pks),
    do: Enum.map(pks, &Map.get(model_or_params, &1))

  defp primary_keys(module) do
    primary_keys =
      case module.__schema__(:primary_key) do
        []  -> raise Ecto.NoPrimaryKeyFieldError, model: module
        pks -> pks
      end
    param_keys = Enum.map(primary_keys, &Atom.to_string/1)

    {primary_keys, param_keys}
  end

  defp put_new_action(%{action: action} = changeset, new_action) when is_nil(action),
    do: Map.put(changeset, :action, new_action)
  defp put_new_action(changeset, _new_action),
    do: changeset

  defp process_current(nil, _pks),
    do: %{}
  defp process_current(current, pks) do
    Enum.into(current, %{}, fn model ->
      {get_pks(model, pks), model}
    end)
  end

  defp skip?(%{valid?: true, changes: empty, action: :update}) when empty == %{},
    do: true
  defp skip?(_changeset),
    do: false

  defp loaded_or_empty!(%{__meta__: %{state: :built}},
                        %Ecto.Association.NotLoaded{} = not_loaded) do
    empty(not_loaded)
  end

  defp loaded_or_empty!(model, %Ecto.Association.NotLoaded{__field__: field}) do
    raise ArgumentError, "attempting to cast or change association `#{field}` " <>
      "of `#{inspect model}` that was not loaded. Please preload your " <>
      "associations before casting or changing the model."
  end

  defp loaded_or_empty!(_model, loaded), do: loaded
end
