defmodule Ecto.Query.Types do
  # Handle casting and type checking in Ecto.
  #
  # This module is only concern about runtime checking
  # of values. Compile time checks are done directly in
  # the Ecto.Query.Builder module.

  @moduledoc false
  import Kernel, except: [match?: 2]

  @type type :: concrete | runtime
  @type concrete :: basic | composite
  @type runtime  :: {non_neg_integer, atom | Macro.t}

  @typep basic     :: :any | :integer | :float | :boolean | :string |
                      :binary | :uuid | :decimal | :datetime | :time | :date
  @typep composite :: {:array, basic}

  @doc """
  Checks if two concrete types match.

      iex> match?(:whatever, :any)
      true
      iex> match?(:any, :whatever)
      true
      iex> match?(:string, :string)
      true
      iex> match?({:list, :string}, {:list, :any})
      true

  """
  @spec match?(concrete, concrete) :: boolean
  def match?({outer, left}, {outer, right}), do: match?(left, right)
  def match?(_left, :any),                   do: true
  def match?(:any, _right),                  do: true
  def match?(type, type),                    do: true
  def match?(_, _),                          do: false

  @doc """
  Casts a value to the given type.
  """
  @spec cast(type, term, sources :: tuple) :: {:ok, term} | :error
  def cast(type, term, sources) do

  end
end