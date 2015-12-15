defmodule Ecto.Changeset.Relation do
  @moduledoc false

  alias Ecto.Changeset
  alias Ecto.Association.NotLoaded

  @type on_replace :: :raise | :mark_as_invalid | :delete | :nilify
  @type t :: %{__struct__: atom, cardinality: :one | :many,
               related: atom, on_replace: on_replace, field: atom}

  @doc """
  Updates the changeset accordingly to the relation's on_replace strategy.
  """
  @callback on_replace(t, Changeset.t) :: {:update | :delete, Changeset.t}

  @doc """
  Builds the related model.
  """
  @callback build(t) :: Ecto.Schema.t

  @doc """
  Returns empty container for relation.
  """
  def empty(%{cardinality: cardinality}), do: do_empty(cardinality)

  defp do_empty(:one), do: nil
  defp do_empty(:many), do: []

  @doc """
  Checks if the container can be considered empty.
  """
  def empty?(%{cardinality: _}, %NotLoaded{}), do: true
  def empty?(%{cardinality: :many}, []), do: true
  def empty?(%{cardinality: :one}, nil), do: true
  def empty?(%{}, _), do: false

  @doc """
  Applies related changeset changes
  """
  def apply_changes(%{cardinality: :one}, nil) do
    nil
  end

  def apply_changes(%{cardinality: :one}, changeset) do
    apply_changes(changeset)
  end

  def apply_changes(%{cardinality: :many}, changesets) do
    for changeset <- changesets,
      model = apply_changes(changeset),
      do: model
  end

  defp apply_changes(%Changeset{action: :delete}), do: nil
  defp apply_changes(changeset), do: Changeset.apply_changes(changeset)

  @doc """
  Loads the relation with the given model.

  Loading will fail if the asociation is not loaded but the model is.
  """
  def load!(%{__meta__: %{state: :built}}, %NotLoaded{__cardinality__: cardinality}) do
    do_empty(cardinality)
  end

  def load!(model, %NotLoaded{__field__: field}) do
    raise ArgumentError, "attempting to cast or change association `#{field}` " <>
      "from `#{inspect model.__struct__}` that was not loaded. Please preload your " <>
      "associations before casting or changing the model"
  end

  def load!(_model, loaded), do: loaded

  @doc """
  Casts related according to the `on_cast` function.
  """
  def cast(%{cardinality: :one} = relation, nil, current, _on_cast) do
    case current && on_replace(relation, current) do
      :error ->
        :error
      _ ->
        {:ok, nil, false, false}
    end
  end

  def cast(%{cardinality: :many} = relation, params, current, on_cast) when is_map(params) do
    params =
      params
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))
    cast(relation, params, current, on_cast)
  end

  def cast(%{related: model} = relation, params, current, on_cast) do
    pks = primary_keys!(model)
    param_pks = Enum.map(pks, &{Atom.to_string(&1), model.__schema__(:type, &1)})
    cast_or_change(relation, params, current, param_pks, pks,
                   &do_cast(relation, &1, &2, on_cast))
  end

  defp do_cast(meta, params, nil, on_cast) do
    {:ok, on_cast.(meta.__struct__.build(meta), params) |> put_new_action(:insert)}
  end

  defp do_cast(relation, nil, current, _cast_casat) do
    on_replace(relation, current)
  end

  defp do_cast(_meta, params, struct, on_cast) do
    {:ok, on_cast.(struct, params) |> put_new_action(:update)}
  end

  @doc """
  Wraps related models in changesets.
  """
  def change(_relation, nil, nil), do: {:ok, nil, false, true}

  def change(%{related: mod} = relation, value, current) do
    pks = primary_keys!(mod)
    cast_or_change(relation, value, current, pks, pks,
                   &do_change(relation, &1, &2))
  end

  # This may be an insert or an update, get all fields.
  defp do_change(%{related: module}, changeset_or_struct, nil) do
    fields    = module.__schema__(:fields)
    embeds    = module.__schema__(:embeds)
    assocs    = module.__schema__(:associations)
    {:ok, Changeset.change(changeset_or_struct)
          |> put_new_action(:insert)
          |> surface(fields, embeds, assocs)}
  end

  defp do_change(relation, nil, current) do
    on_replace(relation, current)
  end

  defp do_change(_relation, %Changeset{model: current} = changeset, current) do
    {:ok, put_new_action(changeset, :update)}
  end

  defp do_change(%{field: field}, %Changeset{}, _current) do
    raise ArgumentError, "cannot change `#{field}` because given changeset has a different " <>
                         "embed/association than the one specified in the parent struct"
  end

  defp do_change(%{field: field}, _struct, _current) do
    raise ArgumentError, "cannot change `#{field}` with a struct because another " <>
                         "embed/association is set in parent struct, use a changeset instead"
  end

  @doc """
  Surface all embeds and associations in the underlying struct
  into the changeset as a change.
  """
  def surface(%{action: :insert} = changeset, fields, embeds, assocs) do
    %{model: struct, types: types} = changeset
    changeset
    |> surface_relations(embeds, types, struct)
    |> surface_relations(assocs, types, struct)
    |> surface_fields(struct, fields -- embeds -- assocs)
  end

  def surface(changeset, _fields, _embeds, _assocs) do
    changeset
  end

  defp surface_fields(changeset, struct, fields) do
    update_in(changeset.changes, &Map.merge(Map.take(struct, fields), &1))
  end

  defp surface_relations(changeset, [], _types, _struct) do
    changeset
  end

  defp surface_relations(%{changes: changes} = changeset, relation, types, struct) do
    {changes, errors} =
      Enum.reduce relation, {changes, []}, fn field, {changes, errors} ->
        case {changes, types} do
          {%{^field => _}, _} ->
            {changes, errors}
          {_, %{^field => {_, embed_or_assoc}}} ->
            # This is partly reimplemeting the logic behind put_relation
            # in Ecto.Changeset but we need to do it in a way where we have
            # control over the current value.
            value = load!(struct, Map.get(struct, field))
            case change(embed_or_assoc, value, nil) do
              {:ok, _, _, true}       -> {changes, errors}
              {:ok, change, _, false} -> {Map.put(changes, field, change), errors}
              :error                  -> {changes, [{field, "is invalid"}]}
            end
          {_, _} ->
            {changes, errors}
        end
      end

    case errors do
      [] -> put_in changeset.changes, changes
      _  -> %{changeset | errors: errors ++ changeset.errors, valid?: false}
    end
  end

  @doc """
  Handles the changeset or model when being replaced.
  """
  def on_replace(%{__struct__: module} = relation, changeset_or_model) do
    case local_on_replace(relation, changeset_or_model) do
      :ok ->
        {action, changeset} =
          module.on_replace(relation, Changeset.change(changeset_or_model))
        {:ok, put_new_action(changeset, action)}
      :error ->
        :error
    end
  end

  defp local_on_replace(%{on_replace: :mark_as_invalid}, _changeset_or_model) do
    :error
  end

  defp local_on_replace(%{on_replace: :raise, field: name, owner: owner}, _) do
    raise """
    you are attempting to change relation #{inspect name} of
    #{inspect owner}, but there is missing data.

    By default, if the parent model contains N children, at least the same
    N children must be given on update. In other words, it is not possible
    to orphan embed nor associated records, attempting to do so results
    in this error message.

    It is possible to change this behaviour by setting `:on_replace` when
    defining the relation. See `Ecto.Changeset`'s section on related models
    for more info.
    """
  end

  defp local_on_replace(_relation, _changeset_or_model) do
    :ok
  end

  defp cast_or_change(%{cardinality: :one} = relation, value, current, param_pks,
                      pks, fun) when is_map(value) or is_nil(value) do
    single_change(relation, value, pks, param_pks, fun, current)
  end

  defp cast_or_change(%{cardinality: :many}, value, current, param_pks, pks, fun) when is_list(value) do
    map_changes(value, pks, param_pks, fun, current)
  end

  defp cast_or_change(_, _, _, _, _, _), do: :error

  # map changes

  defp map_changes(list, pks, param_pks, fun, current) do
    map_changes(list, param_pks, fun, process_current(current, pks), [], true, true)
  end

  defp map_changes([], _pks, fun, current, acc, valid?, skip?) do
    current_models = Enum.map(current, &elem(&1, 1))
    reduce_delete_changesets(current_models, fun, Enum.reverse(acc), valid?, skip?)
  end

  defp map_changes([map | rest], pks, fun, current, acc, valid?, skip?) when is_map(map) do
    pk_values = get_pks(map, pks)

    {model, current, allowed_actions} =
      case Map.fetch(current, pk_values) do
        {:ok, model} ->
          {model, Map.delete(current, pk_values), [:update, :delete]}
        :error ->
          {nil, current, [:insert]}
      end

    case build_changeset!(map, model, fun, allowed_actions) do
      {:ok, changeset} ->
        map_changes(rest, pks, fun, current, [changeset | acc],
                    valid? && changeset.valid?, skip? && skip?(changeset))
      :error ->
        :error
    end
  end

  defp map_changes(_params, _pkd, _fun, _current, _acc, _valid?, _skip?) do
    :error
  end

  defp reduce_delete_changesets([], _fun, acc, valid?, skip?) do
    {:ok, acc, valid?, skip?}
  end

  defp reduce_delete_changesets([model | rest], fun, acc, valid?, skip?) do
    case build_changeset!(nil, model, fun, [:update, :delete]) do
      {:ok, changeset} ->
        reduce_delete_changesets(rest, fun, [changeset | acc],
                                 valid? && changeset.valid?,
                                 skip? && skip?(changeset))
      :error ->
        :error
    end
  end

  # single changes

  defp single_change(_relation, nil, _current_pks, _new_pks, fun, current) do
    single_changeset!(nil, current, fun, [:update, :delete])
  end

  defp single_change(_relation, new, _current_pks, _new_pks, fun, nil) do
    single_changeset!(new, nil, fun, [:insert])
  end

  defp single_change(relation, new, current_pks, new_pks, fun, current) do
    if get_pks(new, new_pks) == get_pks(current, current_pks) do
      single_changeset!(new, current, fun, [:update, :delete])
    else
      case local_on_replace(relation, current) do
        :ok -> single_changeset!(new, nil, fun, [:insert])
        :error -> :error
      end
    end
  end

  # helpers

  defp single_changeset!(new, current, fun, allowed_actions) do
    case build_changeset!(new, current, fun, allowed_actions) do
      {:ok, changeset} ->
        {:ok, changeset, changeset.valid?, skip?(changeset)}
      :error ->
        :error
    end
  end

  defp build_changeset!(new, current, fun, allowed_actions) do
    case fun.(new, current) do
      {:ok, changeset} ->
        action = changeset.action

        if action in allowed_actions do
          {:ok, changeset}
        else
          reason = if action == :insert, do: "already exists", else: "does not exist"
          raise "cannot #{action} related #{inspect changeset.model} " <>
            "because it #{reason} in the parent model"
        end
      :error ->
        :error
    end
  end

  defp get_pks(%Changeset{model: model}, pks),
    do: get_pks(model, pks)
  defp get_pks(model_or_params, pks),
    do: Enum.map(pks, &do_get_pk(model_or_params, &1))

  defp do_get_pk(model_or_params, {key, type}) do
    original = do_get_pk(model_or_params, key)
    case Ecto.Type.cast(type, original) do
      {:ok, value} -> value
      :error       -> original
    end
  end
  defp do_get_pk(model_or_params, key), do: Map.get(model_or_params, key)

  defp primary_keys!(module) do
    case module.__schema__(:primary_key) do
      []  -> raise Ecto.NoPrimaryKeyFieldError, model: module
      pks -> pks
    end
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
end
