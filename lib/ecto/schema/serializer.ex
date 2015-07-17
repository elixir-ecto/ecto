defmodule Ecto.Schema.Serializer do
  @moduledoc false
  alias Ecto.Schema.Metadata

  @doc """
  Loads recursively given model from data.

  Data can be either a map with string keys or a tuple of index and row,
  where index specifies the place in the row, where data for loading model
  starts.
  """
  def load!(model, prefix, source, data, loader) do
    source = source || model.__schema__(:source)
    struct = model.__struct__()
    fields = model.__schema__(:types)

    loaded = do_load(struct, fields, data, loader)
    loaded = Map.put(loaded, :__meta__, %Metadata{state: :loaded, source: {prefix, source}})
    Ecto.Model.Callbacks.__apply__(model, :after_load, loaded)
  end

  defp do_load(struct, fields, map, loader) when is_map(map) do
    Enum.reduce(fields, struct, fn
      {field, type}, acc ->
        value = load!(type, Map.get(map, Atom.to_string(field)), loader)
        Map.put(acc, field, value)
    end)
  end

  defp do_load(struct, fields, list, loader) when is_list(list) do
    Enum.reduce(fields, {struct, list}, fn
      {field, type}, {acc, [h|t]} ->
        value = load!(type, h, loader)
        {Map.put(acc, field, value), t}
    end) |> elem(0)
  end

  defp load!(type, value, loader) do
    case loader.(type, value) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "cannot load `#{inspect value}` as type #{inspect type}"
    end
  end

  @doc """
  Dumps recursively given model's struct.
  """
  def dump!(model, data, dumper) do
    fields = model.__schema__(:types)
    Enum.reduce(fields, %{}, fn {field, type}, acc ->
      value = Map.get(data, field)
      Map.put(acc, field, dumper.(type, value))
    end)
  end
end
