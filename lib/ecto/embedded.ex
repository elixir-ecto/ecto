defmodule Ecto.Embedded do
  @moduledoc false
  alias __MODULE__
  alias Ecto.Changeset

  @type t :: %Embedded{cardinality: :one | :many,
                       on_replace: :raise | :mark_as_invalid | :delete,
                       field: atom,
                       owner: atom,
                       related: atom}

  @behaviour Ecto.Changeset.Relation
  @on_replace_opts [:raise, :mark_as_invalid, :delete]
  defstruct [:cardinality, :field, :owner, :related, on_replace: :raise]

  @doc """
  Builds the embedded struct.

  ## Options

    * `:cardinality` - tells if there is one embedded schema or many
    * `:related` - name of the embedded schema
    * `:on_replace` - the action taken on embeds when the embed is replaced

  """
  def struct(module, name, opts) do
    opts = Keyword.put_new(opts, :on_replace, :raise)

    unless opts[:on_replace] in @on_replace_opts do
      raise ArgumentError, "invalid `:on_replace` option for #{inspect name}. " <>
        "The only valid options are: " <>
        Enum.map_join(@on_replace_opts, ", ", &"`#{inspect &1}`")
    end

    struct(%Embedded{field: name, owner: module}, opts)
  end

  @doc """
  Callback invoked by repository to prepare embeds.

  It replaces the changesets for embeds inside changes
  by actual structs so it can be dumped by adapters and
  loaded into the schema struct afterwards.
  """
  def prepare(changeset, adapter, repo_action) do
    %{changes: changes, model: %{__struct__: schema}} = changeset
    prepare(changeset, Map.take(changes, schema.__schema__(:embeds)), adapter, repo_action)
  end

  defp prepare(changeset, embeds, _adapter, _repo_action) when embeds == %{} do
    changeset
  end

  defp prepare(%{types: types} = changeset, embeds, adapter, repo_action) do
    update_in changeset.changes, fn changes ->
      Enum.reduce embeds, changes, fn {name, changeset}, acc ->
        {:embed, embed} = Map.get(types, name)
        Map.put(acc, name, prepare_each(embed, changeset, adapter, repo_action))
      end
    end
  end

  defp prepare_each(%{cardinality: :one}, nil, _adapter, _repo_action) do
    nil
  end

  defp prepare_each(%{cardinality: :one} = embed, changeset, adapter, repo_action) do
    action = check_action!(changeset.action, repo_action, embed)
    to_struct(changeset, action, embed, adapter)
  end

  defp prepare_each(%{cardinality: :many} = embed, changesets, adapter, repo_action) do
    for changeset <- changesets,
        action = check_action!(changeset.action, repo_action, embed),
        prepared = to_struct(changeset, action, embed, adapter),
        do: prepared
  end

  defp to_struct(%Changeset{valid?: false}, _action,
                 %{related: schema}, _adapter) do
    raise ArgumentError, "changeset for embedded #{inspect schema} is invalid, " <>
                         "but the parent changeset was not marked as invalid"
  end

  defp to_struct(%Changeset{model: %{__struct__: actual}}, _action,
                 %{related: expected}, _adapter) when actual != expected do
    raise ArgumentError, "expected changeset for embedded schema `#{inspect expected}`, " <>
                         "got: #{inspect actual}"
  end

  defp to_struct(%Changeset{changes: changes, model: model}, :update,
                 _embed, _adapter) when changes == %{} do
    model
  end

  defp to_struct(%Changeset{}, :delete, _embed, _adapter) do
    nil
  end

  defp to_struct(%Changeset{types: types} = changeset, action,
                    %{related: schema}, adapter) do
    %{model: struct, changes: changes} = prepare(changeset, adapter, action)

    changes
    |> autogenerate_id(struct, action, schema, adapter)
    |> autogenerate(action, schema, types, adapter)
    |> apply_embeds(struct)
  end

  defp apply_embeds(changes, struct) do
    struct = struct(struct, changes)
    put_in(struct.__meta__.state, :loaded)
  end

  defp check_action!(:replace, action, %{on_replace: :delete} = embed),
    do: check_action!(:delete, action, embed)
  defp check_action!(:update, :insert, %{related: schema}),
    do: raise(ArgumentError, "got action :update in changeset for embedded #{inspect schema} while inserting")
  defp check_action!(:delete, :insert, %{related: schema}),
    do: raise(ArgumentError, "got action :delete in changeset for embedded #{inspect schema} while inserting")
  defp check_action!(action, _, _), do: action

  defp autogenerate_id(changes, _struct, :insert, schema, adapter) do
    case schema.__schema__(:autogenerate_id) do
      {key, :binary_id} ->
        case Map.fetch(changes, key) do
          {:ok, _} ->
            changes
          :error ->
            {:ok, value} = Ecto.Type.adapter_load(adapter, :binary_id, adapter.autogenerate(:embed_id))
            Map.put(changes, key, value)
        end
      other ->
        raise ArgumentError, "embedded schema `#{inspect schema}` must have " <>
          "`:binary_id` primary key with `autogenerate: true`, got: #{inspect other}"
    end
  end

  defp autogenerate_id(changes, struct, :update, _schema, _adapter) do
    for {_, nil} <- Ecto.primary_key(struct) do
      raise Ecto.NoPrimaryKeyValueError, struct: struct
    end
    changes
  end

  defp autogenerate(changes, action, schema, types, adapter) do
    Enum.reduce schema.__schema__(:autogenerate, action), changes, fn {k, mod, args}, acc ->
      case Map.fetch(acc, k) do
        {:ok, _} -> acc
        :error   -> Map.put(acc, k, load!(types, k, apply(mod, :autogenerate, args), adapter))
      end
    end
  end

  defp load!(types, k, v, adapter) do
    type = Map.fetch!(types, k)
    case Ecto.Type.adapter_load(adapter, type, v) do
      {:ok, v} -> v
      :error   -> raise ArgumentError, "cannot load `#{inspect v}` as type #{inspect type}"
    end
  end

  @doc """
  Callback invoked to build relations.
  """
  def build(%Embedded{related: related}) do
    related.__struct__
  end
end
