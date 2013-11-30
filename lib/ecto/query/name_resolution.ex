defmodule Ecto.Query.NameResolution do
  @moduledoc false

  def create_names(query) do
    sources = query.sources |> tuple_to_list
    Enum.reduce(sources, [], fn({ table, entity, model }, names) ->
      name = unique_name(names, String.first(table), 0)
      [{ { table, name }, entity, model }|names]
    end) |> Enum.reverse |> list_to_tuple
  end

  defp unique_name(names, name, counter) do
    counted_name = name <> integer_to_binary(counter)
    if Enum.any?(names, fn { { _, n }, _, _ } -> n == counted_name end) do
      unique_name(names, name, counter+1)
    else
      counted_name
    end
  end
end
