defmodule Ecto.Type.UTCDateTimeUsec do
  @moduledoc false

  @behaviour Ecto.Type

  def type(), do: :utc_datetime_usec

  def cast(binary) when is_binary(binary) do
    case DateTime.from_iso8601(binary) do
      {:ok, datetime, _offset} ->
        cast(datetime)

      {:error, :missing_offset} ->
        case NaiveDateTime.from_iso8601(binary) do
          {:ok, naive_datetime} -> cast(naive_datetime)
          {:error, _} -> :error
        end

      {:error, _} ->
        :error
    end
  end

  def cast(%DateTime{microsecond: {_, 6}, time_zone: "Etc/UTC"} = datetime), do: {:ok, datetime}

  def cast(%DateTime{microsecond: {usec, _}, time_zone: "Etc/UTC"} = datetime),
    do: {:ok, %{datetime | microsecond: {usec, 6}}}

  def cast(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_unix()
    |> DateTime.from_unix()
    |> case do
      {:ok, datetime} -> cast(datetime)
      {:error, _} -> :error
    end
  end

  def cast(%NaiveDateTime{} = naive_datetime),
    do: naive_datetime |> DateTime.from_naive!("Etc/UTC") |> cast()

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
        {:ok, naive_datetime} -> cast(naive_datetime)
        {:error, _} -> :error
      end
    end
  end

  def cast(_), do: :error

  def dump(%DateTime{time_zone: time_zone, microsecond: {_, 6}} = datetime) do
    if time_zone != "Etc/UTC" do
      message =
        ":utc_datetime_usec expects the time zone to be \"Etc/UTC\", got `#{inspect(datetime)}`"

      raise ArgumentError, message
    end

    {:ok, DateTime.to_naive(datetime)}
  end

  def dump(_), do: :error

  def load(%DateTime{} = datetime),
    do: {:ok, pad_usec(datetime)}

  def load(%NaiveDateTime{} = naive_datetime),
    do: naive_datetime |> pad_usec() |> DateTime.from_naive("Etc/UTC")

  def load(_), do: :error

  def equal?(%DateTime{} = a, %DateTime{} = b), do: DateTime.compare(a, b) == :eq
  def equal?(_, _), do: false

  # HELPERS

  defp pad_usec(nil), do: nil
  defp pad_usec(%{microsecond: {_, 6}} = struct), do: struct

  defp pad_usec(%{microsecond: {microsecond, _}} = struct),
    do: %{struct | microsecond: {microsecond, 6}}
end
