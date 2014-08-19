defmodule Ecto.Model.Assign do
  def assign(model, values) do
    values = filtered_keys(model(model), values)
    struct(model, values)
  end

  defp filtered_keys(model, values) do
    field_names = model.__schema__(:field_names)
    binary_field_names = model.__schema__(:field_names) |> Enum.map(&Atom.to_string/1)
    Enum.flat_map values, fn({k, v}) ->
      cond do
        k in field_names -> [{k, v}]
        k in binary_field_names -> [{String.to_atom(k), v}]
        true -> []
      end
    end
  end

  # Given either a model or a struct, return the model
  defp model(module) when is_atom(module), do: module
  defp model(%{__struct__: module} = model), do: module
end
