defprotocol Ecto.DataType do
  @moduledoc """
  Casts and dumps a given struct into an Ecto type.

  While `Ecto.Type` allows developers to cast/load/dump
  any value from the storage into the struct based on the
  schema, `Ecto.DataType` allows developers to convert
  existing data types into primitive Ecto types without
  the schema information.

  For example, Elixir's native `Date` struct implements
  the Ecto.DataType protocol so it is properly converted
  to a tuple when directly passed to adapters:

      defimpl Ecto.DataType, for: Date do
        def dump(%Date{day: day, month: month, year: year}) do
          {:ok, {year, month, day}}
        end
      end

  """
  @fallback_to_any true

  @doc """
  Invoked when the data structure has not been dumped along
  the way and must fallback to its database representation.
  """
  @spec dump(term) :: {:ok, term} | :error
  def dump(value)
end

defimpl Ecto.DataType, for: Any do
  # The default representation is itself, which
  # means we are delegating to the database. If
  # the database does not support, it will raise.
  def dump(value) do
    {:ok, value}
  end
end

defimpl Ecto.DataType, for: List do
  def dump(list), do: dump(list, [])

  defp dump([h|t], acc) do
    case Ecto.DataType.dump(h) do
      {:ok, h} -> dump(t, [h|acc])
      :error -> :error
    end
  end
  defp dump([], acc) do
    {:ok, Enum.reverse(acc)}
  end
end

defimpl Ecto.DataType, for: NaiveDateTime do
  def dump(%NaiveDateTime{year: year, month: month, day: day,
                          hour: hour, minute: minute, second: second, microsecond: {usec, _}}) do
    {:ok, {{year, month, day}, {hour, minute, second, usec}}}
  end
end

defimpl Ecto.DataType, for: DateTime do
  def dump(%DateTime{year: year, month: month, day: day, time_zone: "Etc/UTC",
                     hour: hour, minute: minute, second: second, microsecond: {usec, _}}) do
    {:ok, {{year, month, day}, {hour, minute, second, usec}}}
  end
end

defimpl Ecto.DataType, for: Date do
  def dump(%Date{year: year, month: month, day: day}) do
    {:ok, {year, month, day}}
  end
end

defimpl Ecto.DataType, for: Time do
  def dump(%Time{hour: hour, minute: minute, second: second, microsecond: {usec, _}}) do
    {:ok, {hour, minute, second, usec}}
  end
end
