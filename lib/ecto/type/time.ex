defmodule Ecto.Type.Time do
  @moduledoc false

  @behaviour Ecto.Type

  def type(), do: :time

  def cast(<<hour::2-bytes, ?:, minute::2-bytes>>),
    do: do_cast(to_i(hour), to_i(minute), 0)

  def cast(binary) when is_binary(binary) do
    case Time.from_iso8601(binary) do
      {:ok, time} -> {:ok, truncate_usec(time)}
      {:error, _} -> :error
    end
  end

  def cast(%{"hour" => empty, "minute" => empty}) when empty in ["", nil], do: {:ok, nil}
  def cast(%{hour: empty, minute: empty}) when empty in ["", nil], do: {:ok, nil}

  def cast(%{"hour" => hour, "minute" => minute} = map),
    do: do_cast(to_i(hour), to_i(minute), to_i(Map.get(map, "second")))

  def cast(%{hour: hour, minute: minute} = map),
    do: do_cast(to_i(hour), to_i(minute), to_i(Map.get(map, :second)))

  def cast(_), do: :error

  defp do_cast(hour, minute, sec)
       when is_integer(hour) and is_integer(minute) and (is_integer(sec) or is_nil(sec)) do
    case Time.new(hour, minute, sec || 0, {0, 0}) do
      {:ok, _} = ok -> ok
      {:error, _} -> :error
    end
  end

  defp do_cast(_, _, _), do: :error

  def dump(%Time{microsecond: {0, 0}} = term), do: {:ok, term}
  def dump(_), do: :error

  def load(%Time{} = time), do: {:ok, truncate_usec(time)}
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

  defp truncate_usec(nil), do: nil
  defp truncate_usec(%{microsecond: {0, 0}} = struct), do: struct
  defp truncate_usec(struct), do: %{struct | microsecond: {0, 0}}
end
