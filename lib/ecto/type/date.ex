defmodule Ecto.Type.Date do
  @moduledoc false

  @behaviour Ecto.Type

  def type(), do: :date

  def cast(binary) when is_binary(binary) do
    case Date.from_iso8601(binary) do
      {:ok, _} = ok ->
        ok

      {:error, _} ->
        case NaiveDateTime.from_iso8601(binary) do
          {:ok, naive_datetime} -> {:ok, NaiveDateTime.to_date(naive_datetime)}
          {:error, _} -> :error
        end
    end
  end

  def cast(%{"year" => empty, "month" => empty, "day" => empty}) when empty in ["", nil],
    do: {:ok, nil}

  def cast(%{year: empty, month: empty, day: empty}) when empty in ["", nil], do: {:ok, nil}

  def cast(%{"year" => year, "month" => month, "day" => day}),
    do: do_cast(to_i(year), to_i(month), to_i(day))

  def cast(%{year: year, month: month, day: day}),
    do: do_cast(to_i(year), to_i(month), to_i(day))

  def cast(_), do: :error

  defp do_cast(year, month, day)
       when is_integer(year) and is_integer(month) and is_integer(day) do
    case Date.new(year, month, day) do
      {:ok, _} = ok -> ok
      {:error, _} -> :error
    end
  end

  defp do_cast(_, _, _), do: :error

  def dump(%Date{} = term), do: {:ok, term}
  def dump(_), do: :error

  def load(%Date{} = term), do: {:ok, term}
  def load(_), do: :error

  def equal?(%Date{} = a, %Date{} = b), do: Date.compare(a, b) == :eq
  def equal?(_, _), do: false

  ## Helpers

  defp to_i(nil), do: nil
  defp to_i(int) when is_integer(int), do: int

  defp to_i(bin) when is_binary(bin) do
    case Integer.parse(bin) do
      {int, ""} -> int
      _ -> nil
    end
  end
end
