defmodule Ecto.Schema.Loader do
  @moduledoc false

  alias Ecto.Schema.Metadata

  @doc """
  Loads a struct to be used as a template in further operations.
  """
  def load_struct(nil, _prefix, _source), do: %{}

  def load_struct(schema, prefix, source) do
    case schema.__schema__(:loaded) do
      %{__meta__: %Metadata{prefix: ^prefix, source: ^source}} = struct ->
        struct

      %{__meta__: %Metadata{} = metadata} = struct ->
        Map.put(struct, :__meta__, %{metadata | source: source, prefix: prefix})

      %{} = struct ->
        struct
    end
  end

  @doc """
  Loads data coming from the user/embeds into schema.

  Assumes data does not all belong to schema/struct
  and that it may also require source-based renaming.
  """
  def unsafe_load(schema, data, loader) do
    types = schema.__schema__(:load)
    struct = schema.__schema__(:loaded)
    unsafe_load(struct, types, data, loader)
  end

  @doc """
  Loads data coming from the user/embeds into struct and types.

  Assumes data does not all belong to schema/struct
  and that it may also require source-based renaming.
  """
  def unsafe_load(struct, types, map, loader) when is_map(map) do
    Enum.reduce(types, struct, fn pair, acc ->
      {field, source, type} = field_source_and_type(pair)

      case fetch_string_or_atom_field(map, source) do
        {:ok, value} -> Map.put(acc, field, load!(struct, field, type, value, loader))
        :error -> acc
      end
    end)
  end

  @compile {:inline, field_source_and_type: 1, fetch_string_or_atom_field: 2}
  defp field_source_and_type({field, {:source, source, type}}) do
    {field, source, type}
  end

  defp field_source_and_type({field, type}) do
    {field, field, type}
  end

  defp fetch_string_or_atom_field(map, field) when is_atom(field) do
    case Map.fetch(map, Atom.to_string(field)) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(map, field)
    end
  end

  @compile {:inline, load!: 5}
  defp load!(struct, field, type, value, loader) do
    case loader.(type, value) do
      {:ok, value} ->
        value

      :error ->
        raise ArgumentError,
              "cannot load `#{inspect(value)}` as type #{Ecto.Type.format(type)} " <>
                "for field `#{field}`#{error_data(struct)}"
    end
  end

  defp error_data(%{__struct__: atom}) do
    " in schema #{inspect(atom)}"
  end

  defp error_data(other) when is_map(other) do
    ""
  end

  @doc """
  Dumps the given data.
  """
  def safe_dump(struct, types, dumper) do
    Enum.reduce(types, %{}, fn {field, {source, type, _writable}}, acc ->
      value = Map.get(struct, field)

      case dumper.(type, value) do
        {:ok, value} ->
          Map.put(acc, source, value)
        :error ->
          raise ArgumentError, "cannot dump `#{inspect value}` as type #{Ecto.Type.format(type)} " <>
                               "for field `#{field}` in schema #{inspect struct.__struct__}"
      end
    end)
  end
end
