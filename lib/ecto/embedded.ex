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
    {:ok, changeset_action(mod, fun, :empty, current), false}
  end

  def cast(%Embedded{cardinality: :many, embed: mod, on_cast: fun}, :empty, current) do
    {:ok, Enum.map(current, &changeset_action(mod, fun, :empty, &1)), false}
  end

  def cast(%Embedded{cardinality: :one, embed: mod, on_cast: fun},
           params, current) when is_map(params) do
    {pk, param_pk} = primary_key(mod)
    changeset =
      if current && Map.get(current, pk) == Map.get(params, param_pk) do
        changeset_action(mod, fun, params, current)
      else
        changeset_action(mod, fun, params, nil)
      end
    {:ok, changeset, changeset.valid?}
  end

  def cast(%Embedded{cardinality: :many, embed: mod, on_cast: fun},
           params, current) when is_list(params) do
    {pk, param_pk} = primary_key(mod)
    current = process_current(current, pk)

    changeset_fun = &changeset_action(mod, fun, &1, &2)
    pk_fun = &Map.fetch(&1, param_pk)
    case map_changes(params, pk_fun, changeset_fun, current, [], true, true) do
      {:ok, changesets, valid?, _skip?} -> {:ok, changesets, valid?}
      :error                            -> :error
    end
  end

  def cast(_embed, _params, _current) do
    :error
  end

  @doc """
  Wraps embedded models in changesets.
  """
  def change(_embed, nil, nil), do: {:skip, nil}

  def change(%Embedded{cardinality: :one, embed: mod}, value, current) do
    changeset = do_change(value, current, mod)

    if skip?(changeset) do
      {:skip, changeset}
    else
      {:change, changeset}
    end
  end

  def change(%Embedded{cardinality: :many, embed: mod},
             value, current) when is_list(value) do
    {pk, _} = primary_key(mod)
    current = process_current(current, pk)

    changeset_fun = &do_change(&1, &2, mod)
    pk_fun = &model_or_changeset_pk(&1, pk)
    {:ok, changesets, _valid?, skip?} =
      map_changes(value, pk_fun, changeset_fun, current, [], true, true)

    if skip? do
      {:skip, changesets}
    else
      {:change, changesets}
    end
  end

  defp model_or_changeset_pk(%Changeset{model: model}, pk), do: Map.fetch(model, pk)
  defp model_or_changeset_pk(model, pk), do: Map.fetch(model, pk)

  defp do_change(value, nil, mod) do
    fields    = mod.__schema__(:fields)
    embeds    = mod.__schema__(:embeds)
    changeset = Changeset.change(value)
    types     = changeset.types

    changes =
      Enum.reduce(embeds, Map.take(changeset.model, fields), fn field, acc ->
        {:embed, embed} = Map.get(types, field)
        Map.put(acc, field, change(embed, Map.get(acc, field), nil))
      end)
      |> Map.merge(changeset.changes)

    %{changeset | changes: changes, action: :insert}
  end

  defp do_change(nil, current, mod) do
    # We need to mark all embeds for deletion too
    changes = mod.__schema__(:embeds) |> Enum.map(&{&1, nil})
    %{Changeset.change(current, changes) | action: :delete}
  end

  defp do_change(%Changeset{model: current} = changeset, current, _mod) do
    %{changeset | action: :update}
  end

  defp do_change(%Changeset{}, _current, _mod) do
    raise ArgumentError, "embedded changeset does not change the model already " <>
      "preset in the parent model"
  end

  defp do_change(value, current, _mod) do
    changes = Map.take(value, value.__struct__.__schema__(:fields))
    %{Changeset.change(current, changes) | action: :update}
  end

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
  def apply_callbacks(changeset, [], _adapter, _type), do: changeset

  def apply_callbacks(changeset, embeds, adapter, type) do
    types = changeset.types

    update_in changeset.changes, fn changes ->
      Enum.reduce(embeds, changes, fn name, changes ->
        case Map.fetch(changes, name) do
          {:ok, changeset} ->
            {:embed, embed} = Map.get(types, name)
            Map.put(changes, name, apply_callback(embed, changeset, adapter, type))
          :error ->
            changes
        end
      end)
    end
  end

  defp apply_callback(%Embedded{cardinality: :one}, nil, _adapter, _type) do
    nil
  end

  defp apply_callback(%Embedded{cardinality: :one, embed: model} = embed, changeset, adapter, type) do
    apply_callback(changeset, model, embed, adapter, type)
  end

  defp apply_callback(%Embedded{cardinality: :many, embed: model} = embed, changesets, adapter, type) do
    Enum.map(changesets, &apply_callback(&1, model, embed, adapter, type))
  end

  defp apply_callback(%Changeset{action: :update, changes: changes} = changeset,
                      _model, _embed, _adapter, _type) when changes == %{}, do: changeset

  defp apply_callback(%Changeset{valid?: false}, model, _embed, _adapter, _type) do
    raise ArgumentError, "changeset for #{model} is invalid, " <>
                         "but the parent changeset was not marked as invalid"
  end

  defp apply_callback(%Changeset{model: %{__struct__: model}, action: action} = changeset,
                      model, embed, adapter, type) do
    callback = callback_for(type, action)
    Ecto.Model.Callbacks.__apply__(model, callback, changeset)
    |> generate_id(callback, model, embed, adapter)
    |> apply_callbacks(model.__schema__(:embeds), adapter, type)
  end

  defp apply_callback(%Changeset{model: model}, expected, _embed, _adapter, _type) do
    raise ArgumentError, "expected changeset for embedded model `#{inspect expected}`, " <>
                         "got: #{inspect model}"
  end

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

  defp map_changes([], _pk, fun, current, acc, valid?, skip?) do
    {previous, {valid?, skip?}} =
      Enum.map_reduce(current, {valid?, skip?}, fn {_, model}, {valid?, skip?} ->
        changeset = fun.(nil, model)
        {changeset, {valid? && changeset.valid?, skip? && skip?(changeset)}}
      end)

    {:ok, Enum.reverse(acc, previous), valid?, skip?}
  end

  defp map_changes([map | rest], pk, fun, current, acc, valid?, skip?) when is_map(map) do
    case pk.(map) do
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

  defp primary_key(module) do
    case module.__schema__(:primary_key) do
      [pk] -> {pk, Atom.to_string(pk)}
      _    -> raise ArgumentError,
                "embeded models must have exactly one primary key field"
    end
  end

  defp process_current(nil, _pk),
    do: %{}
  defp process_current(current, pk),
    do: Enum.into(current, %{}, &{Map.get(&1, pk), &1})

  defp changeset_action(mod, fun, params, nil) do
    changeset = apply(mod, fun, [params, mod.__struct__()])
    %{changeset | action: :insert}
  end

  defp changeset_action(_mod, _fun, nil, model) do
    %{Changeset.change(model) | action: :delete}
  end

  defp changeset_action(mod, fun, params, model) do
    changeset = apply(mod, fun, [params, model])
    %{changeset | action: :update}
  end

  defp skip?(%{valid?: true, changes: empty, action: :update}) when empty == %{},
    do: true
  defp skip?(_changeset),
    do: false
end
