defmodule Ecto.Type.NaiveDateTime do
  @moduledoc false

  @behaviour Ecto.Type

  def type(), do: :naive_datetime

  def cast(binary) when is_binary(binary) do
    case NaiveDateTime.from_iso8601(binary) do
      {:ok, naive_datetime} -> {:ok, truncate_usec(naive_datetime)}
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
         {:ok, time} <- Ecto.Type.Time.cast(map) do
      case NaiveDateTime.new(date, time) do
        {:ok, _} = ok -> ok
        {:error, _} -> :error
      end
    end
  end

  def cast(_), do: :error

  def dump(%NaiveDateTime{microsecond: {0, 0}} = term), do: {:ok, term}
  def dump(_), do: :error

  def load(%NaiveDateTime{} = naive_datetime), do: {:ok, truncate_usec(naive_datetime)}
  def load(_), do: :error

  def equal?(%NaiveDateTime{} = a, %NaiveDateTime{} = b), do: NaiveDateTime.compare(a, b) == :eq
  def equal?(_, _), do: false

  ## Helpers

  defp truncate_usec(nil), do: nil
  defp truncate_usec(%{microsecond: {0, 0}} = struct), do: struct
  defp truncate_usec(struct), do: %{struct | microsecond: {0, 0}}
end
