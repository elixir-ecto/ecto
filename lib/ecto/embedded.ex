defmodule Ecto.Embedded do
  @moduledoc false

  alias __MODULE__

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
    map_changes(params, param_pk, mod, fun, current, [], true)
  end

  def cast(_embed, _params, _current) do
    :error
  end

  @doc """
  Wraps embedded models in changesets.
  """
  def change(%Embedded{cardinality: :one}, value) do
    Ecto.Changeset.change(value)
  end

  def change(%Embedded{cardinality: :many, container: :array}, value) do
    Enum.map(value, &Ecto.Changeset.change/1)
  end

  @doc """
  Applies given callback to all models
  """
  def apply_callback(%Embedded{cardinality: :one, embed: module}, changeset, callback) do
    do_apply_callback(changeset, callback, module)
  end

  def apply_callback(%Embedded{cardinality: :many, container: :array, embed: module},
                     changesets, callback) do
    Enum.map(changesets, &do_apply_callback(&1, callback, module))
  end

  defp do_apply_callback(%{valid?: false}, _callback, embed) do
    raise ArgumentError, "Changeset for #{embed} is invalid, " <>
      "but the parent changeset was not marked as invalid"
  end
  defp do_apply_callback(%{model: %{__struct__: embed}} = changeset, callback, embed) do
    Ecto.Model.Callbacks.__apply__(embed, callback, changeset)
  end
  defp do_apply_callback(%{model: model}, _callback, embed) do
    raise ArgumentError, "Expected changeset for embedded model #{embed}, " <>
      "got #{inspect model}"
  end

  defp map_changes([], _pk, mod, fun, current, acc, valid?) do
    {previous, valid?} =
      Enum.map_reduce(current, valid?, fn {_, model}, valid? ->
        changeset = changeset_action(mod, fun, nil, model)
        {changeset, valid? && changeset.valid?}
      end)

    {:ok, Enum.reverse(acc, previous), valid?}
  end

  defp map_changes([map | rest], pk, mod, fun, current, acc, valid?) when is_map(map) do
    case Map.fetch(map, pk) do
      {:ok, pk_value} ->
        {model, current} = Map.pop(current, pk_value)
        changeset = changeset_action(mod, fun, map, model)
        map_changes(rest, pk, mod, fun, current,
                    [changeset | acc], valid? && changeset.valid?)
      :error ->
        changeset = changeset_action(mod, fun, map, nil)
        map_changes(rest, pk, mod, fun, current,
                    [changeset | acc], valid? && changeset.valid?)
    end
  end

  defp map_changes(_params, _pk, _mod, _fun, _current, _acc, _valid?) do
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
    changeset = Ecto.Changeset.change(model)
    %{changeset | action: :delete}
  end

  defp changeset_action(mod, fun, params, model) do
    changeset = apply(mod, fun, [params, model])
    %{changeset | action: :update}
  end
end
