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
  Loads data into struct by assumes fields are properly
  named and belongs to the struct. Types and values are
  zipped together in one pass as they are loaded.
  """
  def adapter_load(struct, types, values, all_nil?, adapter) do
    adapter_load(types, values, [], all_nil?, struct, adapter)
  end

  defp adapter_load([{field, type} | types], [value | values], acc, all_nil?, struct, adapter) do
    all_nil? = all_nil? and value == nil
    value = adapter_load!(struct, field, type, value, adapter)
    adapter_load(types, values, [{field, value} | acc], all_nil?, struct, adapter)
  end

  defp adapter_load([], values, _acc, true, _struct, _adapter) do
    {nil, values}
  end

  defp adapter_load([], values, acc, false, struct, _adapter) do
    {Map.merge(struct, Map.new(acc)), values}
  end

  @doc """
  Loads data coming from the user/embeds into schema.

  Assumes data does not all belongs to schema/struct
  and that it may also require source-based renaming.
  """
  def unsafe_load(schema, data, loader) do
    types = schema.__schema__(:load)
    struct = schema.__schema__(:loaded)
    unsafe_load(struct, types, data, loader)
  end

  @doc """
  Loads data coming from the user/embeds into struct and types.

  Assumes data does not all belongs to schema/struct
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

  @compile {:inline, load!: 5, adapter_load!: 5}
  defp adapter_load!(struct, field, type, value, adapter) do
    case Ecto.Type.adapter_load(adapter, type, value) do
      {:ok, value} -> value
      :error -> bad_load!(field, type, value, struct)
    end
  end

  defp load!(struct, field, type, value, loader) do
    case loader.(type, value) do
      {:ok, value} -> value
      :error -> bad_load!(field, type, value, struct)
    end
  end

  defp bad_load!(field, type, value, struct) do
    raise ArgumentError,
          "cannot load `#{inspect(value)}` as type #{inspect(type)} " <>
            "for field `#{field}`#{error_data(struct)}"
  end

  defp error_data(%{__struct__: atom}) do
    " in schema #{inspect(atom)}"
  end

  defp error_data(other) when is_map(other) do
    ""
  end
end
