defmodule Ecto.Schema.Serializer do
  @moduledoc false
  alias Ecto.Schema.Metadata

  @doc """
  Loads recursively given model from data.

  Data can be either a map with string keys or a tuple of index and row,
  where index specifies the place in the row, where data for loading model
  starts.
  """
  def load!(model, prefix, source, data, id_types) do
    source = source || model.__schema__(:source)
    struct = model.__struct__()
    fields = model.__schema__(:types)

    loaded = do_load(struct, fields, data, id_types)
    loaded = Map.put(loaded, :__meta__, %Metadata{state: :loaded, source: {prefix, source}})
    Ecto.Model.Callbacks.__apply__(model, :after_load, loaded)
  end

  defp do_load(struct, fields, map, id_types) when is_map(map) do
    Enum.reduce(fields, struct, fn
      {field, type}, acc ->
        value = Ecto.Type.load!(type, Map.get(map, Atom.to_string(field)), id_types)
        Map.put(acc, field, value)
    end)
  end

  defp do_load(struct, fields, list, id_types) when is_list(list) do
    Enum.reduce(fields, {struct, list}, fn
      {field, type}, {acc, [h|t]} ->
        value = Ecto.Type.load!(type, h, id_types)
        {Map.put(acc, field, value), t}
    end) |> elem(0)
  end
end
