defmodule Ecto.Embedded do
  @moduledoc false

  alias __MODULE__
  alias Ecto.Changeset

  defstruct [:cardinality, :field, :owner, :related, :on_cast, strategy: :replace]

  @type t :: %Embedded{cardinality: :one | :many,
                       strategy: :replace | atom,
                       field: atom, owner: atom, related: atom, on_cast: atom}

  @doc """
  Builds the embedded struct.

  ## Options

    * `:cardinality` - tells if there is one embedded model or many
    * `:strategy` - which strategy to use when storing items
    * `:related` - name of the embedded model
    * `:on_cast` - the changeset function to call during casting

  """
  def struct(module, name, opts) do
    opts = Keyword.put_new(opts, :on_cast, :changeset)
    struct(%Embedded{field: name, owner: module}, opts)
  end

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

  defp apply_callback(%Embedded{cardinality: :one, related: model} = embed,
                      changeset, adapter, function, type) do
    apply_callback(changeset, model, embed, adapter, function, type)
  end

  defp apply_callback(%Embedded{cardinality: :many, related: model} = embed,
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
    pk = primary_key(model)

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

  defp generate_id(changeset, callback, model, _embed, _adapter)
      when callback in [:before_update, :before_delete] do
    pk = primary_key(model)

    case Map.get(changeset.model, pk) do
      nil ->
        raise Ecto.MissingPrimaryKeyError, struct: changeset.model
      _value ->
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

  defp primary_key(module) do
    case module.__schema__(:primary_key) do
      [pk] -> pk
      _    -> raise ArgumentError,
                "embeded models must have exactly one primary key field"
    end
  end
end
