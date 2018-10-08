defmodule Ecto.Type.NaiveDateTimeUsec do
  @moduledoc false

  @behaviour Ecto.Type

  def type(), do: :naive_datetime_usec

  def cast(binary) when is_binary(binary) do
    case NaiveDateTime.from_iso8601(binary) do
      {:ok, naive_datetime} -> {:ok, pad_usec(naive_datetime)}
      {:error, _} -> :error
    end
  end

  def cast(%{
        "year" => empty,
        "month" => empty,
        "day" => empty,
        "hour" => empty,
        "minute" => empty
      })
      when empty in ["", nil],
      do: {:ok, nil}

  def cast(%{year: empty, month: empty, day: empty, hour: empty, minute: empty})
      when empty in ["", nil],
      do: {:ok, nil}

  def cast(%{} = map) do
    with {:ok, date} <- Ecto.Type.Date.cast(map),
         {:ok, time} <- Ecto.Type.TimeUsec.cast(map) do
      case NaiveDateTime.new(date, time) do
        {:ok, _} = ok -> ok
        {:error, _} -> :error
      end
    end
  end

  def cast(_), do: :error

  def dump(%NaiveDateTime{microsecond: {_, 6}} = term), do: {:ok, term}
  def dump(_), do: :error

  def load(%NaiveDateTime{} = naive_datetime), do: {:ok, pad_usec(naive_datetime)}
  def load(_), do: :error

  def equal?(%NaiveDateTime{} = a, %NaiveDateTime{} = b), do: NaiveDateTime.compare(a, b) == :eq
  def equal?(_, _), do: false

  ## Helpers

  defp pad_usec(nil), do: nil
  defp pad_usec(%{microsecond: {_, 6}} = struct), do: struct

  defp pad_usec(%{microsecond: {microsecond, _}} = struct),
    do: %{struct | microsecond: {microsecond, 6}}
end
