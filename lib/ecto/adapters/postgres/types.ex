defmodule Ecto.Adapters.Postgres.Hstore do

  # Type regexes
  @integer ~r/\A\d+\z/
  @float ~r/\A\d+\.\d+\z/

  def decode(%{} = hstore_map) do
    Enum.reduce hstore_map, %{}, fn ({key, value}, result_map) ->
      Dict.put(result_map, parse_value(key), parse_value(value))
    end
  end

  defp parse_value(nil), do: nil

  defp parse_value("true"), do: true

  defp parse_value("false"), do: false

  defp parse_value(value) when is_binary(value) do
    cond do
      Regex.match?(@integer, value) ->
        String.to_integer(value)
      Regex.match?(@float, value) ->
        String.to_float(value)
      true ->
        value
    end
  end

  defp parse_value(value), do: value
end
