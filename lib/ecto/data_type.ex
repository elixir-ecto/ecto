defprotocol Ecto.DataType do
  @moduledoc """
  Casts and dumps a given struct into an Ecto type.

  While `Ecto.Type` allows developers to cast/load/dump
  any value from the storage into the struct based on the
  schema, `Ecto.DataType` allows developers to convert
  existing data types into existing Ecto types without
  the schema information.

  For example, `Ecto.Date` is a custom type, represented
  by the `%Ecto.Date{}` struct that can be used in place
  of Ecto's primitive `:date` type. Therefore, we need to
  tell Ecto how to convert `%Ecto.Date{}` into `:date`,
  even in the absence of schema information, and such is
  done with the `Ecto.DataType` protocol:

      defimpl Ecto.DataType, for: Ecto.Date do
        # Dumps to the default representation. In this case, :date.
        def dump(value) do
          cast(value, :date)
        end

        # Implement any other desired casting rule.
        def cast(%Ecto.Date{day: day, month: month, year: year}, :date) do
          {:ok, {year, month, day}}
        end

        def cast(_, _) do
          :error
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
  # TODO: Deprecate this casting function when we migrate to Elixir v1.3.
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

defimpl Ecto.DataType, for: Ecto.DateTime do
  def dump(value), do: cast(value, :datetime)

  def cast(%Ecto.DateTime{year: year, month: month, day: day,
                          hour: hour, min: min, sec: sec, usec: usec}, :datetime) do
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
