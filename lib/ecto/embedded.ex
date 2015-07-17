defmodule Ecto.Embedded do
  @moduledoc false

  alias __MODULE__
  alias Ecto.Changeset

  defstruct [:cardinality, :container, :field, :owner, :embed, :on_cast]

  @type t :: %Embedded{cardinality: :one | :many,
                       container: nil | :array | :map,
                       field: atom, owner: atom, embed: atom, on_cast: atom}

  @doc """
  Builds the embedded struct.

  ## Options

    * `:cardinality` - tells if there is one embedded model or many
    * `:container` - container to store many embeds
    * `:embed` - name of the embedded model
    * `:on_cast` - the changeset function to call during casting

  """
  def struct(module, name, opts) do
    %__MODULE__{
      cardinality: Keyword.fetch!(opts, :cardinality),
      container: Keyword.get(opts, :container),
      field: name,
      owner: module,
      embed: Keyword.fetch!(opts, :embed),
      on_cast: Keyword.fetch!(opts, :on_cast)
    }
  end

  @doc """
  Casts embedded models according to the `on_cast` function.

  Sets correct `state` on the returned changeset
  """
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

  def cast(%Embedded{cardinality: :many, container: :array, embed: mod, on_cast: fun},
           params, current) when is_list(params) do
    {pk, param_pk} = primary_key(mod)
    current = process_current(current, pk)

    changeset_fun = &changeset_action(mod, fun, &1, &2)
    pk_fun = &Map.fetch(&1, param_pk)
    map_changes(params, pk_fun, changeset_fun, current, [], true)
  end

  def cast(_embed, _params, _current) do
    :error
  end

  @doc """
  Wraps embedded models in changesets.
  """
  def change(%Embedded{cardinality: :one, embed: mod}, value, current) do
    do_change(value, current, mod)
  end

  # We accept nil here to make is easier to mark embeds recursively
  # for deletion, otherwise we would need to guess what to pass [] or nil
  def change(%Embedded{cardinality: :many, container: :array, embed: mod},
             value, current) when is_list(value) or is_nil(value) do
    {pk, _} = primary_key(mod)
    current = process_current(current, pk)

    changeset_fun = &do_change(&1, &2, mod)
    pk_fun = fn
      %Changeset{model: model} -> Map.fetch(model, pk)
      model -> Map.fetch(model, pk)
    end
    map_changes(value || [], pk_fun, changeset_fun, current, [], true) |> elem(1)
  end

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
  Returns empty container for embed
  """
  def empty(%Embedded{cardinality: :one}), do: nil
  def empty(%Embedded{cardinality: :many, container: :array}), do: []

  @doc """
  Applies embedded changeset changes
  """
  def apply_changes(%Embedded{cardinality: :one}, changeset) do
    do_apply_changes(changeset)
  end

  def apply_changes(%Embedded{cardinality: :many, container: :array}, changesets) do
    changesets
    |> Enum.reduce([], fn changeset, acc ->
      case do_apply_changes(changeset) do
        nil   -> acc
        value -> [value | acc]
      end
    end)
    |> Enum.reverse
  end

  defp do_apply_changes(nil), do: nil
  defp do_apply_changes(%Changeset{action: :delete}), do: nil
  defp do_apply_changes(changeset), do: Changeset.apply_changes(changeset)

  @doc """
  Applies given callback to all models based on changeset action
  """
  def apply_callback(%Embedded{cardinality: :one, embed: module}, changeset, type) do
    do_apply_callback(changeset, type, module)
  end

  def apply_callback(%Embedded{cardinality: :many, container: :array, embed: module},
                     changesets, type) do
    Enum.map(changesets, &do_apply_callback(&1, type, module))
  end

  defp do_apply_callback(nil, _type, _embed), do: nil

  defp do_apply_callback(%{action: :update, changes: changes} = changeset, _, _)
    when changes == %{}, do: changeset

  defp do_apply_callback(%{valid?: false}, _type, embed) do
    raise ArgumentError, "changeset for #{embed} is invalid, " <>
      "but the parent changeset was not marked as invalid"
  end

  defp do_apply_callback(%{model: %{__struct__: embed}, action: action} = changeset,
                         type, embed) do
    Ecto.Model.Callbacks.__apply__(embed, callback_for(type, action), changeset)
  end

  defp do_apply_callback(%{model: model}, _callback, embed) do
    raise ArgumentError, "expected changeset for embedded model #{embed}, " <>
      "got #{inspect model}"
  end

  types = [:before, :after]
  actions = [:insert, :update, :delete]

  for type <- types, action <- actions do
    defp callback_for(unquote(type), unquote(action)), do: unquote(:"#{type}_#{action}")
  end

  defp callback_for(_type, nil) do
    raise ArgumentError, "embedded changeset action not set"
  end

  defp map_changes([], _pk, fun, current, acc, valid?) do
    {previous, valid?} =
      Enum.map_reduce(current, valid?, fn {_, model}, valid? ->
        changeset = fun.(nil, model)
        {changeset, valid? && changeset.valid?}
      end)

    {:ok, Enum.reverse(acc, previous), valid?}
  end

  defp map_changes([map | rest], pk, fun, current, acc, valid?) when is_map(map) do
    case pk.(map) do
      {:ok, pk_value} ->
        {model, current} = Map.pop(current, pk_value)
        changeset = fun.(map, model)
        map_changes(rest, pk, fun, current,
                    [changeset | acc], valid? && changeset.valid?)
      :error ->
        changeset = fun.(map, nil)
        map_changes(rest, pk, fun, current,
                    [changeset | acc], valid? && changeset.valid?)
    end
  end

  defp map_changes(_params, _pk, _fun, _current, _acc, _valid?) do
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
end
