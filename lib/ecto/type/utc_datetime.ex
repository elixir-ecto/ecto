defmodule Ecto.Type.UTCDateTime do
  @moduledoc false

  @behaviour Ecto.Type

  def type(), do: :utc_datetime

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

  def cast(%DateTime{microsecond: {0, 0}, time_zone: "Etc/UTC"} = datetime), do: {:ok, datetime}

  def cast(%DateTime{time_zone: "Etc/UTC"} = datetime),
    do: {:ok, %{datetime | microsecond: {0, 0}}}

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
         {:ok, time} <- Ecto.Type.Time.cast(map) do
      case NaiveDateTime.new(date, time) do
        {:ok, naive_datetime} -> cast(naive_datetime)
        {:error, _} -> :error
      end
    end
  end

  def cast(_), do: :error

  def dump(%DateTime{time_zone: time_zone, microsecond: {0, 0}} = term) do
    if time_zone != "Etc/UTC" do
      message = ":utc_datetime expects the time zone to be \"Etc/UTC\", got `#{inspect(term)}`"
      raise ArgumentError, message
    end

    {:ok, DateTime.to_naive(term)}
  end

  def dump(_), do: :error

  def load(%DateTime{} = datetime),
    do: {:ok, truncate_usec(datetime)}

  def load(%NaiveDateTime{} = naive_datetime),
    do: naive_datetime |> truncate_usec() |> DateTime.from_naive("Etc/UTC")

  def load(_), do: :error

  def equal?(%DateTime{} = a, %DateTime{} = b), do: DateTime.compare(a, b) == :eq
  def equal?(_, _), do: false

  # HELPERS

  defp truncate_usec(nil), do: nil
  defp truncate_usec(%{microsecond: {0, 0}} = struct), do: struct
  defp truncate_usec(struct), do: %{struct | microsecond: {0, 0}}
end
