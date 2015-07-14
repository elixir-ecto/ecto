defmodule Ecto.Embedded do
  @moduledoc """
  The embedding struct for `embeds_one` and `embeds_many`.

  Its fields are:

    * `cardinality` - The association cardinality
    * `field` - The name of the association field on the model
    * `owner` - The model where the association was defined
    * `embed` - The model that is embedded
    * `container` - The type of a container many embeds are stored in
    * `on_cast` - Function name to call by default when casting embeds

  """

  alias __MODULE__

  defstruct [:cardinality, :container, :field, :owner, :embed, :on_cast]

  @type t :: %Embedded{cardinality: :one | :many,
                       container: nil | :array | :map,
                       field: atom, owner: atom, embed: atom, on_cast: atom}

  @doc """
  Builds the embedded struct.

  ## Options

    * `:cardinality` - tells if there is one embedded model or many
    * `:field` - tells the field in the owner struct where the
      embeds should be stored
    * `:owner` - the owner module of the embedding
    * `:owner_key` - the key in the owner with the association value
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
        changeset_status(mod, fun, params, current)
      else
        changeset_status(mod, fun, params, nil)
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
  Wraps embedded models in changesets
  """
  def change(%Embedded{cardinality: :one}, value) do
    Ecto.Changeset.change(value)
  end

  def change(%Embedded{cardinality: :many, container: :array}, value) do
    Enum.map(value, &Ecto.Changeset.change/1)
  end

  defp map_changes([], _pk, mod, fun, current, acc, valid?) do
    {previous, valid?} =
      Enum.map_reduce(current, valid?, fn {_, model}, valid? ->
        changeset = changeset_status(mod, fun, nil, model)
        {changeset, valid? && changeset.valid?}
      end)

    {:ok, Enum.reverse(acc, previous), valid?}
  end

  defp map_changes([map | rest], pk, mod, fun, current, acc, valid?) when is_map(map) do
    case Map.fetch(map, pk) do
      {:ok, pk_value} ->
        {model, current} = Map.pop(current, pk_value)
        changeset = changeset_status(mod, fun, map, model)
        map_changes(rest, pk, mod, fun, current,
                    [changeset | acc], valid? && changeset.valid?)
      :error ->
        changeset = changeset_status(mod, fun, map, nil)
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


  defp changeset_status(mod, fun, params, nil) do
    changeset = apply(mod, fun, [params, mod.__struct__()])
    %{changeset | status: :insert}
  end

  defp changeset_status(_mod, _fun, nil, model) do
    changeset = Ecto.Changeset.change(model)
    %{changeset | status: :delete}
  end

  defp changeset_status(mod, fun, params, model) do
    changeset = apply(mod, fun, [params, model])
    %{changeset | status: :update}
  end
end
