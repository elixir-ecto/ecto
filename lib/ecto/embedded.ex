defmodule Ecto.Embedded do
  @moduledoc false

  alias __MODULE__
  alias Ecto.Changeset

  defstruct [:cardinality, :field, :owner, :embed, :on_cast, strategy: :replace]

  @type t :: %Embedded{cardinality: :one | :many,
                       strategy: :replace | atom,
                       field: atom, owner: atom, embed: atom, on_cast: atom}

  @doc """
  Builds the embedded struct.

  ## Options

    * `:cardinality` - tells if there is one embedded model or many
    * `:strategy` - which strategy to use when storing items
    * `:embed` - name of the embedded model
    * `:on_cast` - the changeset function to call during casting

  """
  def struct(module, name, opts) do
    struct(%__MODULE__{field: name, owner: module}, opts)
  end

  @doc """
  Casts embedded models according to the `on_cast` function.

  Sets correct `state` on the returned changeset
  """
  def cast(%Embedded{cardinality: :one, embed: mod, on_cast: fun}, :empty, current) do
    {:ok, current && do_cast(mod, fun, :empty, current), false, false}
  end

  def cast(%Embedded{cardinality: :many, embed: mod, on_cast: fun}, :empty, current) do
    {:ok, Enum.map(current, &do_cast(mod, fun, :empty, &1)), false, false}
  end

  def cast(%Embedded{cardinality: :one}, nil, _current) do
    {:ok, nil, false, false}
  end

  def cast(%Embedded{cardinality: :many} = embed, params, current) when is_map(params) do
    params =
      params
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))
    cast(embed, params, current)
  end

  def cast(%Embedded{embed: mod, on_cast: fun} = embed, params, current) do
    {pk, param_pk} = primary_key(mod)
    cast_or_change(embed, params, current, param_pk, pk, &do_cast(mod, fun, &1, &2))
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
  def change(_embed, nil, nil), do: {:ok, nil, false, true}

  def change(%Embedded{embed: mod} = embed, value, current) do
    {pk, _} = primary_key(mod)
    cast_or_change(embed, value, current, pk, pk, &do_change(&1, &2, mod))
  end

  defp do_change(value, nil, mod) do
    fields    = mod.__schema__(:fields)
    embeds    = mod.__schema__(:embeds)
    changeset = Changeset.change(value)
    types     = changeset.types

    changes =
      Enum.reduce(embeds, Map.take(changeset.model, fields), fn field, acc ->
        {:embed, embed} = Map.get(types, field)
        case change(embed, Map.get(acc, field), nil) do
          {:ok, _, _, true}       -> acc
          {:ok, change, _, false} -> Map.put(acc, field, change)
        end
      end)
      |> Map.merge(changeset.changes)

    %{changeset | changes: changes} |> put_new_action(:insert)
  end

  defp do_change(nil, current, mod) do
    # We need to mark all embeds for deletion too
    changes = mod.__schema__(:embeds) |> Enum.map(&{&1, nil})
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

  defp cast_or_change(%{cardinality: :one}, value, current, param_pk, pk, fun) when is_map(value) or is_nil(value) do
    single_change(value, param_pk, current, pk, fun)
  end

  defp cast_or_change(%{cardinality: :many}, value, current, param_pk, pk, fun) when is_list(value) do
    map_changes(value, pk, param_pk, fun, current)
  end

  defp cast_or_change(_, _, _, _, _, _), do: :error

  @doc """
  Returns empty container for embed.
  """
  def empty(%Embedded{cardinality: :one}), do: nil
  def empty(%Embedded{cardinality: :many}), do: []

  @doc """
  Applies embedded changeset changes
  """
  def apply_changes(%Embedded{cardinality: :one}, nil) do
    nil
  end

  def apply_changes(%Embedded{cardinality: :one}, changeset) do
    apply_changes(changeset)
  end

  def apply_changes(%Embedded{cardinality: :many}, changesets) do
    for changeset <- changesets,
        model = apply_changes(changeset),
        do: model
  end

  defp apply_changes(%Changeset{action: :delete}), do: nil
  defp apply_changes(changeset), do: Changeset.apply_changes(changeset)

  @doc """
  Applies given callback to all models based on changeset action
  """
  def apply_callbacks(changeset, [], _adapter, _function, _type), do: changeset

  def apply_callbacks(changeset, embeds, adapter, function, type) do
    types = changeset.types

    update_in changeset.changes, fn changes ->
      Enum.reduce(embeds, changes, fn name, changes ->
        case Map.fetch(changes, name) do
          {:ok, changeset} ->
            {:embed, embed} = Map.get(types, name)
            Map.put(changes, name, apply_callback(embed, changeset, adapter, function, type))
          :error ->
            changes
        end
      end)
    end
  end

  defp apply_callback(%Embedded{cardinality: :one}, nil, _adapter, _function, _type) do
    nil
  end

  defp apply_callback(%Embedded{cardinality: :one, embed: model} = embed,
                      changeset, adapter, function, type) do
    apply_callback(changeset, model, embed, adapter, function, type)
  end

  defp apply_callback(%Embedded{cardinality: :many, embed: model} = embed,
                      changesets, adapter, function, type) do
    for changeset <- changesets,
        do: apply_callback(changeset, model, embed, adapter, function, type)
  end

  defp apply_callback(%Changeset{action: :update, changes: changes} = changeset,
                      _model, _embed, _adapter, _function, _type) when changes == %{},
    do: changeset

  defp apply_callback(%Changeset{valid?: false}, model, _embed, _adapter, _function, _type) do
    raise ArgumentError, "changeset for embedded #{model} is invalid, " <>
                         "but the parent changeset was not marked as invalid"
  end

  defp apply_callback(%Changeset{model: %{__struct__: model}, action: action} = changeset,
                      model, embed, adapter, function, type) do
    check_action!(action, function, model)
    callback = callback_for(type, action)
    Ecto.Model.Callbacks.__apply__(model, callback, changeset)
    |> generate_id(callback, model, embed, adapter)
    |> apply_callbacks(model.__schema__(:embeds), adapter, function, type)
  end

  defp apply_callback(%Changeset{model: model}, expected, _embed, _adapter, _function, _type) do
    raise ArgumentError, "expected changeset for embedded model `#{inspect expected}`, " <>
                         "got: #{inspect model}"
  end

  defp check_action!(:update, :insert, model),
    do: raise(ArgumentError, "got action :update in changeset for embedded #{model} while inserting")
  defp check_action!(:delete, :insert, model),
    do: raise(ArgumentError, "got action :delete in changeset for embedded #{model} while inserting")
  defp check_action!(_, _, _), do: :ok

  defp generate_id(changeset, :before_insert, model, embed, adapter) do
    {pk, _} = primary_key(model)

    if Map.get(changeset.changes, pk) == nil and
       Map.get(changeset.model, pk) == nil do
      case model.__schema__(:autogenerate_id) do
        {key, :binary_id} ->
          update_in changeset.changes, &Map.put(&1, key, adapter.embed_id(embed))
        other ->
          raise ArgumentError, "embedded model `#{inspect model}` must have binary id " <>
                               "primary key with autogenerate: true, got: #{inspect other}"
      end
    else
      changeset
    end
  end

  defp generate_id(changeset, _callback, _model, _embed, _adapter) do
    changeset
  end

  types   = [:before, :after]
  actions = [:insert, :update, :delete]

  for type <- types, action <- actions do
    defp callback_for(unquote(type), unquote(action)), do: unquote(:"#{type}_#{action}")
  end

  defp callback_for(_type, nil) do
    raise ArgumentError, "embedded changeset action not set"
  end

  defp map_changes(list, pk, param_pk, fun, current) do
    map_changes(list, param_pk, fun, process_current(current, pk), [], true, true)
  end

  defp map_changes([], _pk, fun, current, acc, valid?, skip?) do
    {previous, {valid?, skip?}} =
      Enum.map_reduce(current, {valid?, skip?}, fn {_, model}, {valid?, skip?} ->
        changeset = fun.(nil, model)
        {changeset, {valid? && changeset.valid?, skip? && skip?(changeset)}}
      end)

    {:ok, Enum.reverse(acc, previous), valid?, skip?}
  end

  defp map_changes([map | rest], pk, fun, current, acc, valid?, skip?) when is_map(map) do
    case get_pk(map, pk) do
      {:ok, pk_value} ->
        {model, current} = Map.pop(current, pk_value)
        changeset = fun.(map, model)
        map_changes(rest, pk, fun, current, [changeset | acc],
                    valid? && changeset.valid?, skip? && skip?(changeset))
      :error ->
        changeset = fun.(map, nil)
        map_changes(rest, pk, fun, current, [changeset | acc],
                    valid? && changeset.valid?, skip? && skip?(changeset))
    end
  end

  defp map_changes(_params, _pk, _fun, _current, _acc, _valid?, _skip?) do
    :error
  end

  defp single_change(new, new_pk, current, current_pk, fun) do
    current = if matching_new(new, new_pk, current, current_pk), do: current, else: nil
    changeset = fun.(new, current)
    {:ok, changeset, changeset.valid?, skip?(changeset)}
  end

  defp matching_new(nil, _new_pk, _current, _current_pk), do: true
  defp matching_new(_new, _new_pk, nil, _current_pk), do: false
  defp matching_new(new, new_pk, current, current_pk),
    do: get_pk(new, new_pk) == get_pk(current, current_pk)

  defp get_pk(%Changeset{model: model}, pk), do: Map.fetch(model, pk)
  defp get_pk(model, pk), do: Map.fetch(model, pk)

  defp primary_key(module) do
    case module.__schema__(:primary_key) do
      [pk] -> {pk, Atom.to_string(pk)}
      _    -> raise ArgumentError,
                "embeded models must have exactly one primary key field"
    end
  end

  defp put_new_action(%{action: action} = changeset, new_action) when is_nil(action),
    do: Map.put(changeset, :action, new_action)
  defp put_new_action(changeset, _new_action),
    do: changeset

  defp process_current(nil, _pk),
    do: %{}
  defp process_current(current, pk),
    do: Enum.into(current, %{}, &{Map.get(&1, pk), &1})

  defp skip?(%{valid?: true, changes: empty, action: :update}) when empty == %{},
    do: true
  defp skip?(_changeset),
    do: false
end
