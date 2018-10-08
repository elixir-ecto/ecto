defmodule Ecto.Type.TimeUsec do
  @moduledoc false

  @behaviour Ecto.Type

  def type(), do: :time_usec

  def cast(<<hour::2-bytes, ?:, minute::2-bytes>>),
    do: do_cast(to_i(hour), to_i(minute), 0, 0)

  def cast(binary) when is_binary(binary) do
    case Time.from_iso8601(binary) do
      {:ok, time} -> {:ok, pad_usec(time)}
      {:error, _} -> :error
    end
  end

  def cast(%{"hour" => empty, "minute" => empty}) when empty in ["", nil], do: {:ok, nil}
  def cast(%{hour: empty, minute: empty}) when empty in ["", nil], do: {:ok, nil}

  def cast(%{"hour" => hour, "minute" => minute} = map),
    do:
      do_cast(
        to_i(hour),
        to_i(minute),
        to_i(Map.get(map, "second")),
        to_i(Map.get(map, "microsecond"))
      )

  def cast(%{hour: hour, minute: minute, second: second, microsecond: {microsecond, _}}),
    do: do_cast(to_i(hour), to_i(minute), to_i(second), to_i(microsecond))

  def cast(%{hour: hour, minute: minute} = map),
    do:
      do_cast(
        to_i(hour),
        to_i(minute),
        to_i(Map.get(map, :second)),
        to_i(Map.get(map, :microsecond))
      )

  def cast(_), do: :error

  defp do_cast(hour, minute, sec, {usec, _precision}), do: do_cast(hour, minute, sec, usec)

  defp do_cast(hour, minute, sec, usec)
       when is_integer(hour) and is_integer(minute) and (is_integer(sec) or is_nil(sec)) and
              (is_integer(usec) or is_nil(usec)) do
    case Time.new(hour, minute, sec || 0, {usec || 0, 6}) do
      {:ok, _} = ok -> ok
      {:error, _} -> :error
    end
  end

  defp do_cast(_, _, _, _), do: :error

  def dump(%Time{microsecond: {_, 6}} = term), do: {:ok, term}
  def dump(_), do: :error

  def load(%Time{} = time), do: {:ok, pad_usec(time)}
  def load(_), do: :error

  def equal?(%Time{} = a, %Time{} = b), do: Time.compare(a, b) == :eq
  def equal?(_, _), do: false

  ## HELPERS

  defp to_i(nil), do: nil
  defp to_i(int) when is_integer(int), do: int

  defp to_i(bin) when is_binary(bin) do
    case Integer.parse(bin) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp pad_usec(nil), do: nil
  defp pad_usec(%{microsecond: {_, 6}} = struct), do: struct

  defp pad_usec(%{microsecond: {microsecond, _}} = struct),
    do: %{struct | microsecond: {microsecond, 6}}
end
