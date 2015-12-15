defmodule Ecto.Embedded do
  @moduledoc false
  alias __MODULE__
  alias Ecto.Changeset

  @type t :: %Embedded{cardinality: :one | :many,
                       on_replace: Changeset.Relation.on_replace,
                       field: atom, owner: atom, related: atom}

  @behaviour Ecto.Changeset.Relation
  @on_replace_opts [:raise, :mark_as_invalid, :delete]
  defstruct [:cardinality, :field, :owner, :related, :on_replace]

  @doc """
  Builds the embedded struct.

  ## Options

    * `:cardinality` - tells if there is one embedded model or many
    * `:related` - name of the embedded model
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
  """
  def prepare(%{types: types}, embeds, adapter, repo_action) do
    for {name, changeset} <- embeds, into: %{} do
      {:embed, embed} = Map.get(types, name)
      {name, prepare_each(embed, changeset, adapter, repo_action)}
    end
  end

  defp prepare_each(%{cardinality: :one}, nil, _adapter, _action) do
    nil
  end

  defp prepare_each(%{cardinality: :one} = embed, changeset, adapter, action) do
    check_action!(changeset.action, action, embed)
    prepare_each(changeset, embed, adapter)
  end

  defp prepare_each(%{cardinality: :many} = embed, changesets, adapter, action) do
    for changeset <- changesets,
        check_action!(changeset.action, action, embed),
        prepared = prepare_each(changeset, embed, adapter),
        do: prepared
  end

  defp prepare_each(%Changeset{valid?: false}, %{related: model}, _adapter) do
    raise ArgumentError, "changeset for embedded #{model} is invalid, " <>
                         "but the parent changeset was not marked as invalid"
  end

  defp prepare_each(%Changeset{model: %{__struct__: model}},
                    %{related: expected}, _adapter) when model != expected do
    raise ArgumentError, "expected changeset for embedded model `#{inspect expected}`, " <>
                         "got: #{inspect model}"
  end

  defp prepare_each(%Changeset{action: :update, changes: changes, model: model},
                    _embed, _adapter) when changes == %{} do
    model
  end

  defp prepare_each(%Changeset{action: :delete}, _embed, _adapter) do
    nil
  end

  defp prepare_each(%Changeset{action: action, changes: changes} = changeset,
                    %{related: model} = embed, adapter) do
    embed_changes = Map.take(changes, model.__schema__(:embeds))

    changeset
    |> prepare(embed_changes, adapter, action)
    |> apply_embeds(changeset)
    |> autogenerate_id(action, model, embed, adapter)
    |> autogenerate(changeset, action, model, adapter)
  end

  defp apply_embeds(embeds, changeset) do
    model = Changeset.apply_changes(changeset)
    model = Map.merge(model, embeds)
    put_in(model.__meta__.state, :loaded)
  end

  defp check_action!(:update, :insert, %{related: model}),
    do: raise(ArgumentError, "got action :update in changeset for embedded #{model} while inserting")
  defp check_action!(:delete, :insert, %{related: model}),
    do: raise(ArgumentError, "got action :delete in changeset for embedded #{model} while inserting")
  defp check_action!(_, _, _), do: :ok

  defp autogenerate_id(struct, :insert, model, embed, adapter) do
    case model.__schema__(:autogenerate_id) do
      {key, :binary_id} ->
        if Map.get(struct, key) do
          struct
        else
          Map.put(struct, key, adapter.embed_id(embed))
        end
      other ->
        raise ArgumentError, "embedded model `#{inspect model}` must have " <>
          "`:binary_id` primary key with `autogenerate: true`, got: #{inspect other}"
    end
  end

  defp autogenerate_id(struct, :update, _model, _embed, _adapter) do
    for {_, nil} <- Ecto.primary_key(struct) do
      raise Ecto.NoPrimaryKeyValueError, struct: struct
    end
    struct
  end

  defp autogenerate(struct, %{types: types}, action, model, adapter) do
    Enum.reduce model.__schema__(:autogenerate, action), struct,
      fn {k, mod, args}, acc ->
        if Map.get(acc, k) do
          acc
        else
          Map.put(acc, k, load!(types, k, apply(mod, :autogenerate, args), adapter))
        end
      end
  end

  defp load!(types, k, v, adapter) do
    type = Map.fetch!(types, k)

    case adapter.load(type, v) do
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

  @doc """
  Callback invoked when replacing relations.
  """
  def on_replace(%Embedded{on_replace: :delete}, changeset) do
    {:delete, changeset}
  end
end
