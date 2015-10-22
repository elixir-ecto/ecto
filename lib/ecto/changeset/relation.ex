defmodule Ecto.Changeset.Relation do
  @moduledoc false

  use Behaviour
  alias Ecto.Changeset
  alias Ecto.Association.NotLoaded

  @type on_cast :: atom
  @type on_replace :: :raise | :mark_as_invalid | :delete | :nilify
  @type t :: %{__struct__: atom, cardinality: :one | :many, related: atom,
               on_cast: on_cast, on_replace: on_replace}

  @doc """
  Updates the changeset accordingly to the relation's on_replace strategy.
  """
  defcallback on_replace(t, Changeset.t) :: {:update | :delete, Changeset.t}

  @doc """
  The action to be performed when the relation is modified given the changeset
  on the repo insert/update/delete.
  """
  defcallback on_repo_action(t, Changeset.t, Ecto.Model.t, Ecto.Adapter.t, Ecto.Repo.t,
                             repo_action :: :insert | :update | :delete, Keyword.t) ::
              {:ok, Ecto.Model.t} | {:error, Ecto.Changeset.t}

  @doc """
  Builds the related model.
  """
  defcallback build(t) :: Ecto.Model.t

  @doc """
  Returns empty container for relation.

  Handles both the relation structs as well as Ecto.Association.NotLoaded.
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
  Performs the repository action in the related changeset, returning
  `{:ok, model}` or `{:error, changeset}`.
  """
  def on_repo_action(changeset, related, _adapter, _repo, _opts) when related == %{} do
    {:ok, changeset}
  end

  def on_repo_action(changeset, related, adapter, repo, opts) do
    %Changeset{types: types, model: model, changes: changes, action: action} = changeset

    {model, changes, valid?} =
      Enum.reduce(related, {model, changes, true}, fn {field, changeset}, acc ->
        case Map.get(types, field) do
          {_, related} ->
            on_repo_action(related, field, changeset, adapter, repo, action, opts, acc)
          _ ->
            raise ArgumentError,
              "cannot #{action} `#{field}` in #{inspect model.__struct__}. Only embedded models, " <>
              "has_one and has_many associations can be changed alongside the parent model"
        end
      end)

    if valid? do
      {:ok, %{changeset | model: model}}
    else
      {:error, %{changeset | changes: changes}}
    end
  end

  defp on_repo_action(%{cardinality: :one}, field, nil,
                      _adapter, _repo, _action, _opts, {parent, changes, valid?}) do
    {Map.put(parent, field, nil), Map.put(changes, field, nil), valid?}
  end

  defp on_repo_action(%{cardinality: :one} = meta, field, changeset,
                      adapter, repo, action, opts, {parent, changes, valid?}) do
    case meta.__struct__.on_repo_action(meta, changeset, parent, adapter, repo, action, opts) do
      {:ok, model} ->
        {Map.put(parent, field, model), Map.put(changes, field, changeset), valid?}
      {:error, changeset} ->
        {parent, Map.put(changes, field, changeset), false}
    end
  end

  defp on_repo_action(%{cardinality: :many} = meta, field, changesets,
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
  Casts embedded models according to the `on_cast` function.

  Sets correct `state` on the returned changeset
  """
  def cast(%{cardinality: :one} = relation, nil, current) do
    case current && on_replace(relation, current) do
      :error ->
        :error
      _ ->
        {:ok, nil, false, false}
    end
  end

  def cast(%{cardinality: :many} = relation, params, current) when is_map(params) do
    params =
      params
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))
    cast(relation, params, current)
  end

  def cast(%{related: model} = relation, params, current) do
    pks = primary_keys!(model)
    param_pks = Enum.map(pks, &{Atom.to_string(&1), model.__schema__(:type, &1)})
    cast_or_change(relation, params, current, param_pks, pks,
                   &do_cast(relation, &1, &2))
  end

  defp do_cast(%{related: model, on_cast: fun} = meta, params, nil) do
    {:ok, apply(model, fun, [meta.__struct__.build(meta), params])
          |> put_new_action(:insert)}
  end

  defp do_cast(relation, nil, current) do
    on_replace(relation, current)
  end

  defp do_cast(%{related: model, on_cast: fun}, params, struct) do
    {:ok, apply(model, fun, [struct, params])
          |> put_new_action(:update)}
  end

  @doc """
  Wraps embedded models in changesets.
  """
  def change(_relation, _model, nil, nil), do: {:ok, nil, false, true}

  def change(%{related: mod} = relation, model, value, current) do
    current = load!(model, current)
    pks     = primary_keys!(mod)
    cast_or_change(relation, value, current, pks, pks,
                   &do_change(relation, &1, &2))
  end

  defp do_change(%{related: model}, struct, nil) do
    fields    = model.__schema__(:fields)
    embeds    = model.__schema__(:embeds)
    assocs    = model.__schema__(:associations)
    changeset = Changeset.change(struct)
    struct    = changeset.model
    types     = changeset.types

    changes =
      Enum.reduce(embeds ++ assocs, Map.take(struct, fields), fn field, acc ->
        case Map.fetch(types, field) do
          {:ok, {_, embed_or_assoc}} ->
            value = load!(struct, Map.get(struct, field))
            case change(embed_or_assoc, struct, value, nil) do
              {:ok, _, _, true}       -> acc
              {:ok, change, _, false} -> Map.put(acc, field, change)
            end
          :error ->
            acc
        end
      end)

    {:ok, changeset.changes
          |> update_in(&Map.merge(changes, &1))
          |> put_new_action(:insert)}
  end

  defp do_change(relation, nil, current) do
    on_replace(relation, current)
  end

  defp do_change(_relation, %Changeset{model: current} = changeset, current) do
    {:ok, put_new_action(changeset, :update)}
  end

  defp do_change(_relation, %Changeset{}, _current) do
    raise ArgumentError, "related changeset has a different model than the one specified in the schema"
  end

  defp do_change(_relation, struct, current) do
    changes = Map.take(struct, struct.__struct__.__schema__(:fields))
    {:ok, Changeset.change(current, changes)
          |> put_new_action(:update)}
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

    It is possible to change this behaviour by setting :on_replace when
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
