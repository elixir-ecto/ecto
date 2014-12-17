defmodule Ecto.Query.API do
  use Ecto.Query.Typespec

  @moduledoc """
  The Query API available by default in Ecto queries.

  All queries in Ecto are typesafe and this module defines all
  database functions based on their type. Note that this module defines
  only the API, each database adapter still needs to support the
  functions outlined here.
  """

  ## Types

  deft float
  deft integer
  deft decimal
  deft boolean
  deft binary
  deft string
  deft array(var)
  deft datetime
  deft date
  deft time
  deft interval

  defa number :: decimal | float | integer

  ## Operators

  @doc "Boolean not."
  def not(arg)
  defs not(boolean) :: boolean

  @doc "Equality."
  def left == right
  defs number == number :: boolean
  defs var == var       :: boolean

  @doc "Inequality."
  def left != right
  defs number != number :: boolean
  defs var != var       :: boolean

  @doc "Left less than or equal to right."
  def left <= right
  defs number <= number :: boolean
  defs var <= var       :: boolean

  @doc "Left greater than or equal to right."
  def left >= right
  defs number >= number :: boolean
  defs var >= var       :: boolean

  @doc "Left less than right."
  def left < right
  defs number < number :: boolean
  defs var < var       :: boolean

  @doc "Left greater than right."
  def left > right
  defs number > number :: boolean
  defs var > var       :: boolean

  @doc "Boolean and."
  def left and right
  defs boolean and boolean :: boolean

  @doc "Boolean or."
  def left or right
  defs boolean or boolean :: boolean

  @doc "Returns `true` if argument is null."
  def is_nil(arg)
  defs is_nil(_) :: boolean

  @doc """
  Return `true` if `left` is in `right` array, `false`
  otherwise.
  """
  def left in right
  defs var in array(var) :: boolean

  ## Functions

  @doc """
  References a field. This can be used when a field needs
  to be dynamically referenced.

  ## Examples

      x = :title
      from(p in Post, select: field(p, ^x))

  """
  def field(_var, _atom), do: raise "field/2 should have been expanded"

  @doc """
  Casts a list to an array.

  ## Example

      ids = [1, 2, 3]
      from(c in Comment, where c.id in array(^ids, :integer)

  """
  def array(_list, _atom), do: raise "array/2 should have been expanded"

  @doc """
  Casts a binary literal to a binary type. By default a
  binary literal is of the string type.
  """
  def binary(_string), do: raise "binary/1 should have been expanded"

  @doc """
  Casts a binary literal to a `uuid` type. By default a
  binary literal is of the string type.
  """
  def uuid(_string), do: raise "uuid/1 should have been expanded"

  @doc "Case-insensitive pattern match."
  def ilike(left, right)
  defs ilike(string, string) :: boolean

  @doc "Case-sensitive pattern match."
  def like(left, right)
  defs like(string, string) :: boolean

  ## Aggregate functions

  @doc "Aggregate function, averages the given field over the current group."
  @aggregate true
  def avg(numbers)
  defs avg(number) :: number

  @doc """
  Aggregate function, counts the number of occurrences of the given field
  in the current group.
  """
  @aggregate true
  def count(arg)
  defs count(_) :: integer

  @doc """
  Aggregate function, the maximum number of the given field in the current
  group.
  """
  @aggregate true
  def max(numbers)
  defs max(integer) :: integer
  defs max(float) :: float
  defs max(date) :: date
  defs max(datetime) :: datetime
  defs max(time) :: time

  @doc """
  Aggregate function, the minimum number of the given field in the current
  group.
  """
  @aggregate true
  def min(numbers)
  defs min(integer) :: integer
  defs min(float) :: float
  defs min(date) :: date
  defs min(datetime) :: datetime
  defs min(time) :: time

  @doc "Aggregate function, sums the given field over the current group."
  @aggregate true
  def sum(numbers)
  defs sum(integer) :: integer
  defs sum(float) :: float
end
