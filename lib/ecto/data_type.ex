defprotocol Ecto.DataType do
  @moduledoc """
  Casts a given data type into an `Ecto.Type`.

  While `Ecto.Type` allows developers to cast/load/dump
  any value from the storage into the struct based on the
  schema, `Ecto.DataType` allows developers to convert
  existing data types into existing Ecto types, be them
  primitive or custom.

  For example, `Ecto.Date` is a custom type, represented
  by the `%Ecto.Date{}` struct that can be used in place
  of Ecto's primitive `:date` type. Therefore, we need to
  tell Ecto how to convert `%Ecto.Date{}` into `:date` and
  such is done with the `Ecto.DataType` protocol:

      defimpl Ecto.DataType, for: Ecto.Date do
        def cast(%Ecto.Date{day: day, month: month, year: year}, :date) do
          {:ok, {year, month, day}}
        end
        def cast(_, _) do
          :error
        end
      end

  """
  @fallback_to_any true
  def cast(value, type)
end

defimpl Ecto.DataType, for: Any do
  def cast(_value, _type) do
    :error
  end
end
