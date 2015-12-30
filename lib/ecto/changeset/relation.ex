defmodule Ecto.Changeset.Relation do
  @moduledoc false

  alias Ecto.Changeset
  alias Ecto.Association.NotLoaded

  @type t :: %{cardinality: :one | :many,
               on_replace: :raise | :mark_as_invalid | atom,
               relationship: :parent | :child,
               owner: atom,
               related: atom,
               field: atom}

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
    raise "attempting to cast or change association `#{field}` " <>
          "from `#{inspect model.__struct__}` that was not loaded. Please preload your " <>
          "associations before casting or changing the model"
  end

  def load!(_model, loaded), do: loaded

  @doc """
  Casts related according to the `on_cast` function.
  """
  def cast(%{cardinality: :one} = relation, nil, current, _on_cast) do
    case current && on_replace(relation, current) do
      :error -> :error
      _ -> {:ok, nil, true, is_nil(current)}
    end
  end

  def cast(%{cardinality: :many} = relation, params, current, on_cast) when is_map(params) do
    params =
      params
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))
    cast(relation, params, current, on_cast)
  end

  def cast(%{related: mod} = relation, params, current, on_cast) do
    pks = primary_keys!(mod)
    cast_or_change(relation, params, current, struct_pk(mod, pks),
                   param_pk(mod, pks), &do_cast(relation, &1, &2, &3, on_cast))
  end

  defp do_cast(meta, params, nil, allowed_actions, on_cast) do
    {:ok,
      on_cast.(meta.__struct__.build(meta), params)
      |> put_new_action(:insert)
      |> check_action!(allowed_actions)}
  end

  defp do_cast(relation, nil, current, _allowed_actions, _on_cast) do
    on_replace(relation, current)
  end

  defp do_cast(_meta, params, struct, allowed_actions, on_cast) do
    {:ok,
      on_cast.(struct, params)
      |> put_new_action(:update)
      |> check_action!(allowed_actions)}
  end

  @doc """
  Wraps related models in changesets.
  """
  def change(%{cardinality: :one} = relation, nil, current) do
    case current && on_replace(relation, current) do
      :error -> :error
      _ -> {:ok, nil, true, is_nil(current)}
    end
  end

  def change(%{related: mod} = relation, value, current) do
    get_pks = struct_pk(mod, primary_keys!(mod))
    cast_or_change(relation, value, current, get_pks, get_pks,
                   &do_change(relation, &1, &2, &3))
  end

  # This may be an insert or an update, get all fields.
  defp do_change(_relation, changeset_or_struct, nil, _allowed_actions) do
    changeset = Changeset.change(changeset_or_struct)
    %{model: %{__meta__: %{state: state}}} = changeset
    action =
      case state do
        :built   -> :insert
        :loaded  -> :update
        :deleted -> :delete
      end
    {:ok, put_new_action(changeset, action)}
  end

  defp do_change(relation, nil, current, _allowed_actions) do
    on_replace(relation, current)
  end

  defp do_change(_relation, %Changeset{model: current} = changeset, current, allowed_actions) do
    {:ok, put_new_action(changeset, :update) |> check_action!(allowed_actions)}
  end

  defp do_change(%{field: field}, %Changeset{}, _current, _allowed_actions) do
    raise "cannot change `#{field}` because given changeset has a different " <>
          "embed/association than the one specified in the parent struct"
  end

  defp do_change(%{field: field}, _struct, _current, _allowed_actions) do
    raise "cannot change `#{field}` with a struct because another " <>
          "embed/association is set in parent struct, use a changeset instead"
  end

  @doc """
  Handles the changeset or model when being replaced.
  """
  def on_replace(%{on_replace: :mark_as_invalid}, _changeset_or_model) do
    :error
  end

  def on_replace(%{on_replace: :raise, field: name, owner: owner}, _) do
    raise """
    you are attempting to change relation #{inspect name} of
    #{inspect owner}, but there is missing data.

    If you are attempting to update an existing entry, please make sure
    you include the entry primary key (ID) alongside the data.

    If you have a relationship with many children, at least the same N
    children must be given on update. By default it is not possible to
    orphan embed nor associated records, attempting to do so results in
    this error message.

    It is possible to change this behaviour by setting `:on_replace` when
    defining the relation. See `Ecto.Changeset`'s section on related data
    for more info.
    """
  end

  def on_replace(_relation, changeset_or_model) do
    {:ok, Changeset.change(changeset_or_model) |> put_new_action(:replace)}
  end

  defp cast_or_change(%{cardinality: :one} = relation, value, current, current_pks,
                      new_pks, fun) when is_map(value) or is_nil(value) do
    single_change(relation, value, current_pks, new_pks, fun, current)
  end

  defp cast_or_change(%{cardinality: :many}, value, current, current_pks,
                      new_pks, fun) when is_list(value) do
    map_changes(value, current_pks, new_pks, fun, current)
  end

  defp cast_or_change(_, _, _, _, _, _), do: :error

  # single change

  defp single_change(_relation, nil, _current_pks, _new_pks, fun, current) do
    single_change(nil, current, fun, [:update, :delete], false)
  end

  defp single_change(_relation, new, _current_pks, _new_pks, fun, nil) do
    single_change(new, nil, fun, [:insert], false)
  end

  defp single_change(relation, new, current_pks, new_pks, fun, current) do
    if new_pks.(new) == current_pks.(current) do
      single_change(new, current, fun, [:update, :delete], true)
    else
      case on_replace(relation, current) do
        {:ok, _} -> single_change(new, nil, fun, [:insert], false)
        :error   -> :error
      end
    end
  end

  defp single_change(new, current, fun, allowed_actions, skippable?) do
    case fun.(new, current, allowed_actions) do
      {:ok, changeset} ->
        {:ok, changeset, changeset.valid?, skippable? and skip?(changeset)}
      :error ->
        :error
    end
  end

  # map changes

  defp map_changes(list, current_pks, new_pks, fun, current) do
    map_changes(list, new_pks, fun, process_current(current, current_pks), [], true, true)
  end

  defp map_changes([], _pks, fun, current, acc, valid?, skip?) do
    current_models = Enum.map(current, &elem(&1, 1))
    reduce_delete_changesets(current_models, fun, Enum.reverse(acc), valid?, skip?)
  end

  defp map_changes([map | rest], new_pks, fun, current, acc, valid?, skip?) when is_map(map) do
    pk_values = new_pks.(map)

    {model, current, allowed_actions} =
      case Map.fetch(current, pk_values) do
        {:ok, model} ->
          {model, Map.delete(current, pk_values), [:update, :delete]}
        :error ->
          {nil, current, [:insert]}
      end

    case fun.(map, model, allowed_actions) do
      {:ok, changeset} ->
        map_changes(rest, new_pks, fun, current, [changeset | acc],
                    valid? && changeset.valid?, (model != nil) and skip? and skip?(changeset))
      :error ->
        :error
    end
  end

  defp map_changes(_params, _pks, _fun, _current, _acc, _valid?, _skip?) do
    :error
  end

  defp reduce_delete_changesets([], _fun, acc, valid?, skip?) do
    {:ok, acc, valid?, skip?}
  end

  defp reduce_delete_changesets([model | rest], fun, acc, valid?, _skip?) do
    case fun.(nil, model, [:update, :delete]) do
      {:ok, changeset} ->
        reduce_delete_changesets(rest, fun, [changeset | acc],
                                 valid? && changeset.valid?, false)
      :error ->
        :error
    end
  end

  # helpers

  defp check_action!(changeset, allowed_actions) do
    action = changeset.action

    cond do
      action in allowed_actions ->
        changeset
      action == :insert ->
        raise "cannot #{action} related #{inspect changeset.model} " <>
              "because it is already associated to the given struct"
      true ->
        raise "cannot #{action} related #{inspect changeset.model} because " <>
              "it already exists and it is not currently associated to the " <>
              "given struct. Ecto forbids casting existing records through " <>
              "the association field for security reasons. Instead, set " <>
              "the foreign key value accordingly"
    end
  end

  defp process_current(nil, _get_pks),
    do: %{}
  defp process_current(current, get_pks) do
    Enum.reduce(current, %{}, fn model, acc ->
      Map.put(acc, get_pks.(model), model)
    end)
  end

  defp struct_pk(_mod, pks) do
    fn
      %Changeset{model: model} -> Enum.map(pks, &Map.get(model, &1))
      model -> Enum.map(pks, &Map.get(model, &1))
    end
  end

  defp param_pk(mod, pks) do
    pks = Enum.map(pks, &{Atom.to_string(&1), mod.__schema__(:type, &1)})
    fn params ->
      Enum.map pks, fn {key, type} ->
        original = Map.get(params, key)
        case Ecto.Type.cast(type, original) do
          {:ok, value} -> value
          :error       -> original
        end
      end
    end
  end

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

  defp skip?(%{valid?: true, changes: empty, action: :update}) when empty == %{},
    do: true
  defp skip?(_changeset),
    do: false
end
