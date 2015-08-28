defmodule Ecto.Changeset.Relation do
  @moduledoc false

  use Behaviour
  alias Ecto.Changeset
  alias Ecto.Association.NotLoaded

  @type t :: %{__struct__: atom, cardinality: :one | :many, related: atom, on_cast: atom}

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
  Casts embedded models according to the `on_cast` function.

  Sets correct `state` on the returned changeset
  """
  def cast(relation, model, params, current) do
    cast(relation, params, loaded_or_empty!(model, current))
  end

  defp cast(%{cardinality: :one} = relation, :empty, current) do
    {:ok, current && do_cast(relation, :empty, current), false, false}
  end

  defp cast(%{cardinality: :many} = relation, :empty, current) do
    {:ok, Enum.map(current, &do_cast(relation, :empty, &1)), false, false}
  end

  defp cast(%{cardinality: :one}, nil, _current) do
    {:ok, nil, false, false}
  end

  defp cast(%{cardinality: :many} = relation, params, current) when is_map(params) do
    params =
      params
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))
    cast(relation, params, current)
  end

  defp cast(%{related: model} = relation, params, current) do
    pks = primary_keys!(model)
    param_pks = Enum.map(pks, &{Atom.to_string(&1), model.__schema__(:type, &1)})
    cast_or_change(relation, params, current, param_pks, pks,
                   &do_cast(relation, &1, &2))
  end

  defp do_cast(%{related: model, on_cast: fun}, params, nil) do
    apply(model, fun, [model.__struct__(), params]) |> put_new_action(:insert)
  end

  defp do_cast(%{__struct__: module} = relation, nil, struct) do
    changeset = Changeset.change(struct)
    {action, changeset} = module.on_replace(relation, changeset)
    changeset |> put_new_action(action)
  end

  defp do_cast(%{related: model, on_cast: fun}, params, struct) do
    apply(model, fun, [struct, params]) |> put_new_action(:update)
  end

  @doc """
  Wraps embedded models in changesets.
  """
  def change(_relation, _model, nil, nil), do: {:ok, nil, false, true}

  def change(%{related: mod} = relation, model, value, current) do
    current = loaded_or_empty!(model, current)
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
            value = loaded_or_empty!(struct, Map.get(struct, field))
            case change(embed_or_assoc, struct, value, nil) do
              {:ok, _, _, true}       -> acc
              {:ok, change, _, false} -> Map.put(acc, field, change)
            end
          :error ->
            acc
        end
      end)

    changeset.changes
    |> update_in(&Map.merge(changes, &1))
    |> put_new_action(:insert)
  end

  defp do_change(%{__struct__: module} = relation, nil, current) do
    {action, changeset} =
      module.on_replace(relation, Changeset.change(current))
    changeset |> put_new_action(action)
  end

  defp do_change(_relation, %Changeset{model: current} = changeset, current) do
    changeset |> put_new_action(:update)
  end

  defp do_change(_relation, %Changeset{}, _current) do
    raise ArgumentError, "related changeset has a different model than the one specified in the schema"
  end

  defp do_change(_relation, struct, current) do
    changes = Map.take(struct, struct.__struct__.__schema__(:fields))
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
    {changesets, valid?, skip?} =
      Enum.reduce(current, {Enum.reverse(acc), valid?, skip?}, fn
        {_, model}, {changesets, valid?, skip?} ->
          changeset = fun.(nil, model)
          {[changeset | changesets],
           valid? && changeset.valid?,
           skip? && skip?(changeset)}
      end)

    {:ok, changesets, valid?, skip?}
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
  defp current_or_nil(new, new_pks, current, current_pks) do
    new_pk_values = get_pks(new, new_pks)

    cond do
      current && new_pk_values == get_pks(current, current_pks) ->
        current
      Enum.all?(new_pk_values, &is_nil/1) ->
        nil
      true ->
        raise Ecto.UnmachedRelationError, new_value: new, old_value: current,
                                          cardinality: :one
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

  defp loaded_or_empty!(%{__meta__: %{state: :built}},
                        %NotLoaded{__cardinality__: cardinality}) do
    do_empty(cardinality)
  end

  defp loaded_or_empty!(model, %NotLoaded{__field__: field}) do
    raise ArgumentError, "attempting to cast or change association `#{field}` " <>
      "from `#{inspect model.__struct__}` that was not loaded. Please preload your " <>
      "associations before casting or changing the model"
  end

  defp loaded_or_empty!(_model, loaded), do: loaded
end
