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

      defimpl Ecto.DataType, for: Ecto.Date do
        def dump(%Date{day: day, month: month, year: year}) do
          {:ok, {year, month, day}}
        end
      end

  """
  @fallback_to_any true

  @doc """
  Invoked when the data structure has not been cast along the
  way and must fallback to its database representation.
  """
  @spec dump(term) :: {:ok, term} | :error
  def dump(value)

  @doc """
  Invoked when attempting to cast this data structure to another type.
  """
  # TODO: Remove this callback on Ecto v2.2
  @spec cast(term, Ecto.Type.t) :: {:ok, term} | :error
  def cast(value, type)
end

defimpl Ecto.DataType, for: Any do
  # We don't provide any automatic casting rule.
  def cast(_value, _type) do
    :error
  end

  # The default representation is itself, which
  # means we are delegating to the database. If
  # the database does not support, it will raise.
  def dump(value) do
    {:ok, value}
  end
end

defimpl Ecto.DataType, for: List do
  def dump(list), do: dump(list, [])
  def cast(_, _), do: :error

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

# TODO: Remove Ecto.Date|Time types on Ecto v2.2
defimpl Ecto.DataType, for: Ecto.DateTime do
  def dump(value), do: cast(value, :naive_datetime)

  def cast(%Ecto.DateTime{year: year, month: month, day: day,
                          hour: hour, min: min, sec: sec, usec: usec}, :naive_datetime) do
    {:ok, {{year, month, day}, {hour, min, sec, usec}}}
  end

  def cast(_, _) do
    :error
  end
end

defimpl Ecto.DataType, for: Ecto.Date do
  def dump(value), do: cast(value, :date)

  def cast(%Ecto.Date{year: year, month: month, day: day}, :date) do
    {:ok, {year, month, day}}
  end

  def cast(_, _) do
    :error
  end
end

defimpl Ecto.DataType, for: Ecto.Time do
  def dump(value), do: cast(value, :time)

  def cast(%Ecto.Time{hour: hour, min: min, sec: sec, usec: usec}, :time) do
    {:ok, {hour, min, sec, usec}}
  end

  def cast(_, _) do
    :error
  end
end
