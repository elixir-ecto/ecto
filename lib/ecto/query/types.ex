defmodule Ecto.Query.Types do
  # Handle casting and type checking in Ecto.
  #
  # This module is only concern about runtime checking
  # of values. Compile time checks are done directly in
  # the Ecto.Query.Builder module.

  @moduledoc false
  import Kernel, except: [match?: 2]

  @type type :: basic | composite

  @typep basic     :: :any | :integer | :float | :boolean | :string |
                      :binary | :uuid | :decimal | :datetime | :time | :date
  @typep composite :: {:array, basic}

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
  Casts a value to the given type.

      iex> cast(:any, "whatever")
      {:ok, "whatever"}
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

  def cast(:any, term), do: {:ok, term}
  def cast(_type, nil), do: {:ok, nil}

  def cast(:integer, term) when is_integer(term), do: {:ok, term}
  def cast(:integer, term) when is_binary(term) do
    case Integer.parse(term) do
      {int, ""} -> {:ok, int}
      _         -> :error
    end
  end

  def cast(:float, term) when is_float(term), do: {:ok, term}
  def cast(:float, term) when is_binary(term) do
    case Float.parse(term) do
      {float, ""} -> {:ok, float}
      _           -> :error
    end
  end

  def cast(:boolean, term) when is_boolean(term),    do: {:ok, term}
  def cast(:boolean, term) when term in ~w(true 1),  do: {:ok, true}
  def cast(:boolean, term) when term in ~w(false 0), do: {:ok, false}

  def cast(type, %Ecto.Query.Tagged{type: type} = term), do: {:ok, term}

  def cast(binary, term) when binary in ~w(binary uuid string)a and
                              is_binary(term), do: {:ok, term}

  def cast(:decimal, %Decimal{} = decimal), do: {:ok, decimal}
  def cast(:decimal, term) when is_binary(term) do
    {:ok, Decimal.new(term)} # TODO: Add Decimal.parse/1
  rescue
    Decimal.Error -> :error
  end

  def cast({:array, type}, term) when is_list(term) do
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
  def cast(:date, %Ecto.Date{} = date), do: {:ok, date}
  def cast(:time, %Ecto.Time{} = time), do: {:ok, time}
  def cast(:datetime, %Ecto.DateTime{} = datetime), do: {:ok, datetime}

  def cast(_, _), do: :error
end
