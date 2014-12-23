defmodule Ecto.Query.Types do
  # Handle casting and type checking in Ecto.
  #
  # This module is only concern about runtime checking
  # of values. Compile time checks are done directly in
  # the Ecto.Query.Builder module.

  @moduledoc false
  import Kernel, except: [match?: 2]

  @type type      :: primitive | custom
  @type primitive :: basic | composite
  @type custom    :: module

  @typep basic     :: :any | :integer | :float | :boolean | :string |
                      :binary | :uuid | :decimal | :datetime | :time | :date
  @typep composite :: {:array, basic}

  @basic     ~w(any integer float boolean string binary uuid decimal datetime time date)a
  @composite ~w(array)a

  @doc """
  Checks if we have a primitive type.
  """
  @spec primitive?(primitive) :: true
  @spec primitive?(term) :: false
  def primitive?({composite, basic}) when basic in @basic and composite in @composite, do: true
  def primitive?(basic) when basic in @basic, do: true
  def primitive?(_), do: false

  @doc """
  Checks if two types match.

      iex> match?(:whatever, :any)
      true
      iex> match?(:any, :whatever)
      true
      iex> match?(:string, :string)
      true
      iex> match?({:list, :string}, {:list, :any})
      true

  """
  @spec match?(type, type) :: boolean
  def match?({outer, left}, {outer, right}), do: match?(left, right)
  def match?(_left, :any),                   do: true
  def match?(:any, _right),                  do: true
  def match?(type, type),                    do: true
  def match?(_, _),                          do: false

  @doc """
  Dumps a value to the given type.

  Opposite to casting, dumping is strict. The value must
  be of the given type or an error happens. For such reasons,
  `:any` is not an allowed type for dumping.

  The difference is that `dump/2` calls the `dump/1`
  callback in custom types (instead of `cast/1`).
  """
  @spec dump(type, term) :: {:ok, term} | :error

  def dump(type, value) when type != :any do
    if of_type?(type, value) do
      {:ok, value}
    else
      :error
    end
  end

  @doc """
  Casts a value to the given type.

  `cast/2` is used by the finder queries and assignment
  to cast outside values to inner Ecto values.

      iex> cast(:any, "whatever")
      {:ok, "whatever"}

      iex> cast(:any, nil)
      {:ok, nil}
      iex> cast(:string, nil)
      {:ok, nil}

      iex> cast(:integer, 1)
      {:ok, 1}
      iex> cast(:integer, "1")
      {:ok, 1}
      iex> cast(:integer, "1.0")
      :error

      iex> cast(:float, 1.0)
      {:ok, 1.0}
      iex> cast(:float, "1")
      {:ok, 1.0}
      iex> cast(:float, "1.0")
      {:ok, 1.0}
      iex> cast(:float, "1-foo")
      :error

      iex> cast(:boolean, true)
      {:ok, true}
      iex> cast(:boolean, false)
      {:ok, false}
      iex> cast(:boolean, "1")
      {:ok, true}
      iex> cast(:boolean, "0")
      {:ok, false}
      iex> cast(:boolean, "whatever")
      :error

      iex> cast(:string, "beef")
      {:ok, "beef"}
      iex> cast(:uuid, "beef")
      {:ok, "beef"}
      iex> cast(:binary, "beef")
      {:ok, "beef"}

      iex> cast(:decimal, Decimal.new(1.0))
      {:ok, Decimal.new(1.0)}
      iex> cast(:decimal, Decimal.new("1.0"))
      {:ok, Decimal.new(1.0)}

      iex> cast({:array, :integer}, [1, 2, 3])
      {:ok, [1, 2, 3]}
      iex> cast({:array, :integer}, ["1", "2", "3"])
      {:ok, [1, 2, 3]}
      iex> cast({:array, :string}, [1, 2, 3])
      :error
      iex> cast(:string, [1, 2, 3])
      :error

  """
  @spec cast(type, term) :: {:ok, term} | :error

  def cast(type, value) do
    if of_type?(type, value) do
      {:ok, value}
    else
      do_cast(type, value)
    end
  end

  defp do_cast(:integer, term) when is_binary(term) do
    case Integer.parse(term) do
      {int, ""} -> {:ok, int}
      _         -> :error
    end
  end

  defp do_cast(:float, term) when is_binary(term) do
    case Float.parse(term) do
      {float, ""} -> {:ok, float}
      _           -> :error
    end
  end

  defp do_cast(:boolean, term) when term in ~w(true 1),  do: {:ok, true}
  defp do_cast(:boolean, term) when term in ~w(false 0), do: {:ok, false}

  defp do_cast(:decimal, term) when is_binary(term) do
    {:ok, Decimal.new(term)} # TODO: Add Decimal.parse/1
  rescue
    Decimal.Error -> :error
  end

  defp do_cast({:array, type}, term) when is_list(term) do
    {:ok, Enum.map(term, fn x ->
      case cast(type, x) do
        {:ok, cast} -> cast
        :error -> throw :error
      end
    end)}
  catch
    :error -> :error
  end

  # TODO: Add date/time/datetime parsing?
  defp do_cast(_, _), do: :error

  @doc """
  Checks if a value is of the given primitive type.

  Note that nil matches any type as data stores allows
  nil to be set on any column.

      iex> of_type?(:any, "whatever")
      true
      iex> of_type?(:any, nil)
      true

      iex> of_type?(:string, nil)
      true
      iex> of_type?(:string, "foo")
      true
      iex> of_type?(:string, 1)
      false

      iex> of_type?(:integer, 1)
      true
      iex> of_type?(:integer, "1")
      false
  """
  @spec of_type?(primitive, term) :: boolean

  def of_type?(:any, _), do: true
  def of_type?(_, nil),  do: true

  def of_type?(:float, term),   do: is_float(term)
  def of_type?(:integer, term), do: is_integer(term)
  def of_type?(:boolean, term), do: is_boolean(term)

  def of_type?(binary, term) when binary in ~w(binary uuid string)a, do: is_binary(term)

  def of_type?({:array, type}, term),
    do: is_list(term) and Enum.all?(term, &of_type?(type, &1))

  def of_type?(:decimal, %Decimal{}), do: true
  def of_type?(:date, %Ecto.Date{}),  do: true
  def of_type?(:time, %Ecto.Time{}),  do: true
  def of_type?(:datetime, %Ecto.DateTime{}), do: true
  def of_type?(struct, _) when struct in ~w(decimal date time datetime)a, do: false
end
