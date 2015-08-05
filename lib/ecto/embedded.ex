defmodule Ecto.Embedded do
  @moduledoc false

  alias __MODULE__
  alias Ecto.Changeset

  defstruct [:cardinality, :field, :owner, :related, :on_cast,
             strategy: :replace, on_replace: :delete, on_delete: :fetch_and_delete]

  @type t :: %Embedded{cardinality: :one | :many,
                       strategy: :replace | atom,
                       on_replace: :delete,
                       on_delete: :fetch_and_delete,
                       field: atom, owner: atom, related: atom, on_cast: atom}

  @behaviour Ecto.Changeset.Relation

  @doc false
  def on_replace(%Embedded{on_replace: :delete}, changeset) do
    {:delete, changeset}
  end

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
  Applies given callback to all models based on changeset action
  """
  def apply_callbacks(changeset, [], _adapter, _function, _type), do: changeset

  def apply_callbacks(changeset, embeds, adapter, function, type) do
    types = changeset.types
    model = changeset.model

    update_in changeset.changes, fn changes ->
      Enum.reduce(embeds, changes, fn name, changes ->
        case Map.fetch(changes, name) do
          {:ok, changeset} ->
            {:embed, embed} = Map.get(types, name)
            current = Map.get(model, name)
            Map.put(changes, name, apply_callback(embed, changeset, current, adapter, function, type))
          :error ->
            changes
        end
      end)
    end
  end

  defp apply_callback(%{cardinality: :one}, nil, _current, _adapter, _function, _type) do
    nil
  end

  defp apply_callback(%{cardinality: :one, related: model} = embed,
                      changeset, current, adapter, function, type) do
    changeset = apply_callback(changeset, model, embed, adapter, function, type)
    callback_one_replace!(changeset.action, type, embed, current)
    changeset
  end

  defp apply_callback(%{cardinality: :many, related: model} = embed,
                      changesets, _current, adapter, function, type) do
    for changeset <- changesets,
      do: apply_callback(changeset, model, embed, adapter, function, type)
  end

  defp apply_callback(%Changeset{action: :update, changes: changes} = changeset,
                      _model, _embed, _adapter, _function, _type) when changes == %{} do
    changeset
  end

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

  defp callback_one_replace!(:insert, :after, %{related: model}, current) when current != nil do
    changeset = Changeset.change(current)
    changeset = Ecto.Model.Callbacks.__apply__(model, :before_delete, changeset)
    Ecto.Model.Callbacks.__apply__(model, :after_delete, changeset)
  end
  defp callback_one_replace!(_action, _type, _embed, _current), do: :ok

  defp generate_id(changeset, :before_insert, model, embed, adapter) do
    case model.__schema__(:autogenerate_id) do
      {key, :binary_id} ->
        if Map.get(changeset.changes, key) || Map.get(changeset.model, key) do
          changeset
        else
          update_in changeset.changes, &Map.put(&1, key, adapter.embed_id(embed))
        end
      other ->
        raise ArgumentError, "embedded model `#{inspect model}` must have " <>
          "`:binary_id` primary key with `autogenerate: true`, got: #{inspect other}"
    end
  end

  defp generate_id(changeset, callback, _model, _embed, _adapter)
      when callback in [:before_update, :before_delete] do
    Enum.each(Ecto.Model.primary_key(changeset.model), fn
      {_, nil} -> raise Ecto.NoPrimaryKeyValueError, struct: changeset.model
      _        -> :ok
    end)

    changeset
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
end
