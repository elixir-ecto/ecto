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
  Callback invoked by repository to prepare embeds.
  """
  def prepare(changeset, [], _adapter, _repo_action), do: changeset

  def prepare(changeset, embeds, adapter, repo_action) do
    types     = changeset.types
    changeset = merge_delete_changes(changeset, embeds, types, repo_action)

    update_in changeset.changes, fn changes ->
      Enum.reduce(embeds, changes, fn name, changes ->
        case Map.fetch(changes, name) do
          {:ok, changeset} ->
            {:embed, embed} = Map.get(types, name)
            Map.put(changes, name, prepare_each(embed, changeset, adapter, repo_action))
          :error ->
            changes
        end
      end)
    end
  end

  defp merge_delete_changes(changeset, embeds, types, :delete) do
    changes =
      Enum.map(embeds, fn field ->
        {:embed, embed} = Map.get(types, field)
        {field, Ecto.Changeset.Relation.empty(embed)}
      end)
    Changeset.change(changeset, changes)
  end

  defp merge_delete_changes(changeset, _, _, _), do: changeset

  defp prepare_each(%{cardinality: :one}, nil, _adapter, _action) do
    nil
  end

  defp prepare_each(%{cardinality: :one} = embed, changeset, adapter, action) do
    check_action!(changeset.action, action, embed)
    prepare_each(changeset, embed, adapter)
  end

  defp prepare_each(%{cardinality: :many} = embed, changesets, adapter, action) do
    for changeset <- changesets do
      check_action!(changeset.action, action, embed)
      prepare_each(changeset, embed, adapter)
    end
  end

  defp prepare_each(%Changeset{valid?: false}, %{related: model}, _adapter) do
    raise ArgumentError, "changeset for embedded #{model} is invalid, " <>
                         "but the parent changeset was not marked as invalid"
  end

  defp prepare_each(%Changeset{action: :update, changes: changes} = changeset,
                    _embed, _adapter) when changes == %{} do
    {:ok, changeset}
  end

  defp prepare_each(%Changeset{model: %{__struct__: model}, action: action} = changeset,
                    %{related: model} = embed, adapter) do
    callback = callback_for(:before, action)
    Ecto.Model.Callbacks.__apply__(model, callback, changeset)
    |> generate_id(action, model, embed, adapter)
    |> prepare(model.__schema__(:embeds), adapter, action)
  end

  defp prepare_each(%Changeset{model: model}, %{related: expected}, _adapter) do
    raise ArgumentError, "expected changeset for embedded model `#{inspect expected}`, " <>
                         "got: #{inspect model}"
  end

  defp check_action!(:update, :insert, %{related: model}),
    do: raise(ArgumentError, "got action :update in changeset for embedded #{model} while inserting")
  defp check_action!(:delete, :insert, %{related: model}),
    do: raise(ArgumentError, "got action :delete in changeset for embedded #{model} while inserting")
  defp check_action!(_, _, _), do: :ok

  defp generate_id(changeset, :insert, model, embed, adapter) do
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

  defp generate_id(changeset, action, _model, _embed, _adapter) when action in [:update, :delete] do
    for {_, nil} <- Ecto.Model.primary_key(changeset.model) do
      raise Ecto.NoPrimaryKeyValueError, struct: changeset.model
    end
    changeset
  end

  @doc false
  def on_replace(%Embedded{on_replace: :delete}, changeset) do
    {:delete, changeset}
  end

  @doc false
  def on_repo_action(%{field: field, related: model} = embed,
                     changeset, parent, adapter, repo, _repo_action, opts) do
    changeset = on_repo_action(changeset, model, adapter, repo, opts)
    maybe_replace_one!(embed, changeset.action, Map.get(parent, field))

    if changeset.action == :delete do
      {:ok, nil}
    else
      {:ok, Changeset.apply_changes(changeset)}
    end
  end

  defp on_repo_action(%Changeset{action: :update, changes: changes} = changeset,
                      _model, _adapter, _repo, _opts) when changes == %{} do
    changeset
  end

  defp on_repo_action(%Changeset{action: action, changes: changes} = changeset,
                      model, adapter, repo, opts) do
    callback = callback_for(:after, action)
    related  = Map.take(changes, model.__schema__(:embeds))
    {:ok, changeset} =
      Ecto.Changeset.Relation.on_repo_action(changeset, related, adapter, repo, opts)
    Ecto.Model.Callbacks.__apply__(model, callback, changeset)
  end

  defp maybe_replace_one!(%{cardinality: :one, related: model}, :insert, current) when current != nil do
    changeset = Changeset.change(current)
    changeset = Ecto.Model.Callbacks.__apply__(model, :before_delete, changeset)
    Ecto.Model.Callbacks.__apply__(model, :after_delete, changeset)
    :ok
  end
  defp maybe_replace_one!(_embed, _action, _current), do: :ok

  types   = [:before, :after]
  actions = [:insert, :update, :delete]

  for type <- types, action <- actions do
    defp callback_for(unquote(type), unquote(action)), do: unquote(:"#{type}_#{action}")
  end

  defp callback_for(_type, nil) do
    raise ArgumentError, "embedded changeset action not set"
  end
end
