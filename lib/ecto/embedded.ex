defmodule Ecto.Embedded do
  @moduledoc false
  alias __MODULE__
  alias Ecto.Changeset

  @type t :: %Embedded{cardinality: :one | :many,
                       on_replace: :raise | :mark_as_invalid | :delete,
                       field: atom,
                       owner: atom,
                       on_cast: nil | fun,
                       related: atom,
                       unique: boolean}

  @behaviour Ecto.Changeset.Relation
  @on_replace_opts [:raise, :mark_as_invalid, :delete]
  @embeds_one_on_replace_opts @on_replace_opts ++ [:update]
  defstruct [:cardinality, :field, :owner, :related, :on_cast, on_replace: :raise,
             unique: true, ordered: true]

  @doc """
  Builds the embedded struct.

  ## Options

    * `:cardinality` - tells if there is one embedded schema or many
    * `:related` - name of the embedded schema
    * `:on_replace` - the action taken on embeds when the embed is replaced

  """
  def struct(module, name, opts) do
    opts = Keyword.put_new(opts, :on_replace, :raise)
    cardinality = Keyword.fetch!(opts, :cardinality)
    on_replace_opts = if cardinality == :one, do: @embeds_one_on_replace_opts, else: @on_replace_opts

    unless opts[:on_replace] in on_replace_opts do
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
  def prepare(changeset, embeds, adapter, repo_action) do
    %{changes: changes, types: types, repo: repo} = changeset
    prepare(Map.take(changes, embeds), types, adapter, repo, repo_action)
  end

  defp prepare(embeds, _types, _adapter, _repo, _repo_action) when embeds == %{} do
    embeds
  end

  defp prepare(embeds, types, adapter, repo, repo_action) do
    Enum.reduce embeds, embeds, fn {name, changeset_or_changesets}, acc ->
      {:embed, embed} = Map.get(types, name)
      Map.put(acc, name, prepare_each(embed, changeset_or_changesets, adapter, repo, repo_action))
    end
  end

  defp prepare_each(%{cardinality: :one}, nil, _adapter, _repo, _repo_action) do
    nil
  end

  defp prepare_each(%{cardinality: :one} = embed, changeset, adapter, repo, repo_action) do
    action = check_action!(changeset.action, repo_action, embed)
    changeset = run_prepare(changeset, repo)
    to_struct(changeset, action, embed, adapter)
  end

  defp prepare_each(%{cardinality: :many} = embed, changesets, adapter, repo, repo_action) do
    for changeset <- changesets,
        action = check_action!(changeset.action, repo_action, embed),
        changeset = run_prepare(changeset, repo),
        prepared = to_struct(changeset, action, embed, adapter),
        do: prepared
  end

  defp to_struct(%Changeset{valid?: false}, _action,
                 %{related: schema}, _adapter) do
    raise ArgumentError, "changeset for embedded #{inspect schema} is invalid, " <>
                         "but the parent changeset was not marked as invalid"
  end

  defp to_struct(%Changeset{data: %{__struct__: actual}}, _action,
                 %{related: expected}, _adapter) when actual != expected do
    raise ArgumentError, "expected changeset for embedded schema `#{inspect expected}`, " <>
                         "got: #{inspect actual}"
  end

  defp to_struct(%Changeset{changes: changes, data: schema}, :update,
                 _embed, _adapter) when changes == %{} do
    schema
  end

  defp to_struct(%Changeset{}, :delete, _embed, _adapter) do
    nil
  end

  defp to_struct(%Changeset{} = changeset, action, %{related: schema}, adapter) do
    %{data: struct, changes: changes} = changeset
    embeds = prepare(changeset, schema.__schema__(:embeds), adapter, action)

    changes
    |> Map.merge(embeds)
    |> autogenerate_id(struct, action, schema, adapter)
    |> autogenerate(action, schema)
    |> apply_embeds(struct)
  end

  defp run_prepare(changeset, repo) do
    changeset = %{changeset | repo: repo}

    Enum.reduce(Enum.reverse(changeset.prepare), changeset, fn fun, acc ->
      case fun.(acc) do
        %Ecto.Changeset{} = acc -> acc
        other ->
          raise "expected function #{inspect fun} given to Ecto.Changeset.prepare_changes/2 " <>
                "to return an Ecto.Changeset, got: `#{inspect other}`"
      end
    end)
  end

  defp apply_embeds(changes, struct) do
    struct(struct, changes)
  end

  defp check_action!(:replace, action, %{on_replace: :delete} = embed),
    do: check_action!(:delete, action, embed)
  defp check_action!(:update, :insert, %{related: schema}),
    do: raise(ArgumentError, "got action :update in changeset for embedded #{inspect schema} while inserting")
  defp check_action!(action, _, _), do: action

  defp autogenerate_id(changes, _struct, :insert, schema, adapter) do
    case schema.__schema__(:autogenerate_id) do
      {key, _source, :binary_id} ->
        Map.put_new_lazy(changes, key, fn -> adapter.autogenerate(:embed_id) end)
      {_key, :id} ->
        raise ArgumentError, "embedded schema `#{inspect schema}` cannot autogenerate `:id` primary keys, " <>
                             "those are typically used for auto-incrementing constraints. " <>
                             "Maybe you meant to use `:binary_id` instead?"
      nil ->
        changes
    end
  end

  defp autogenerate_id(changes, struct, :update, _schema, _adapter) do
    for {_, nil} <- Ecto.primary_key(struct) do
      raise Ecto.NoPrimaryKeyValueError, struct: struct
    end
    changes
  end

  defp autogenerate(changes, action, schema) do
    autogen_fields = action |> action_to_auto() |> schema.__schema__()

    Enum.reduce(autogen_fields, changes, fn {fields, {mod, fun, args}}, acc ->
      case Enum.reject(fields, &Map.has_key?(changes, &1)) do
        [] ->
          acc

        fields ->
          generated = apply(mod, fun, args)
          Enum.reduce(fields, acc, &Map.put(&2, &1, generated))
      end
    end)
  end

  defp action_to_auto(:insert), do: :autogenerate
  defp action_to_auto(:update), do: :autoupdate

  @impl true
  def build(%Embedded{related: related}, _owner) do
    related.__struct__
  end
end
