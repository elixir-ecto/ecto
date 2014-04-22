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
  deft nil

  defa number :: decimal | float | integer

  ## Operators

  @doc "Positive number."
  def (+arg)
  defs (+integer) :: integer
  defs (+float)   :: float
  defs (+decimal) :: decimal

  @doc "Negate number."
  def (-arg)
  defs (-integer) :: integer
  defs (-float)   :: float
  defs (-decimal) :: decimal

  @doc "Boolean not."
  def not(arg)
  defs not(boolean) :: boolean

  @doc "Addition of numbers."
  def left + right
  defs decimal + number  :: decimal
  defs number + decimal  :: decimal
  defs float + number    :: float
  defs number + float    :: float
  defs integer + integer :: integer

  @doc "Subtraction of numbers."
  def left - right
  defs decimal - number  :: decimal
  defs number - decimal  :: decimal
  defs float - number    :: float
  defs number - float    :: float
  defs integer - integer :: integer

  @doc "Multiplication of numbers."
  def left * right
  defs decimal * number  :: decimal
  defs number * decimal  :: decimal
  defs float * number    :: float
  defs number * float    :: float
  defs integer * integer :: integer

  @doc "Division of numbers."
  def left / right
  defs number / number   :: decimal

  @doc "Equality."
  def left == right
  defs number == number :: boolean
  defs var == var       :: boolean
  defs nil == _         :: boolean
  defs _ == nil         :: boolean

  @doc "Inequality."
  def left != right
  defs number != number :: boolean
  defs var != var       :: boolean
  defs nil != _         :: boolean
  defs _ != nil         :: boolean

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

  @doc """
  Return `true` if `left` is in `right` array, `false`
  otherwise.
  """
  def left in right
  defs var in array(var) :: boolean

  @doc "Range from left to right."
  def left .. right
  defs integer .. integer :: array(integer)

  @doc "Binary and string concatenation."
  def left <> right
  defs binary <> binary :: binary
  defs string <> string :: string

  @doc "List concatenation."
  def left ++ right
  defs array(var) ++ array(var) :: array(var)

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
  Casts a binary literal to a binary type. By default a
  binary literal is of the string type.
  """
  def binary(_string), do: raise "binary/1 should have been expanded"

  @doc "Addition of datetime's with interval's"
  def time_add(left, right)
  defs time_add(datetime, interval) :: datetime
  defs time_add(interval, datetime) :: datetime
  defs time_add(date, interval)     :: date
  defs time_add(interval, date)     :: date
  defs time_add(time, interval)     :: time
  defs time_add(interval, time)     :: time
  defs time_add(interval, interval) :: interval

  @doc "Subtraction of datetime's with interval's"
  def time_sub(left, right)
  defs time_sub(datetime, interval) :: datetime
  defs time_sub(interval, datetime) :: datetime
  defs time_sub(date, interval)     :: date
  defs time_sub(interval, date)     :: date
  defs time_sub(time, interval)     :: time
  defs time_sub(interval, time)     :: time
  defs time_sub(interval, interval) :: interval

  @doc "base to the power of exp."
  def pow(base, exp)
  defs pow(float, number) :: float
  defs pow(number, float) :: float
  defs pow(integer, integer) :: integer

  @doc "Integer division."
  def div(left, right)
  defs div(integer, integer) :: integer

  @doc "Integer remainder of division."
  def rem(left, right)
  defs rem(integer, integer) :: integer

  @doc "Random float number from 0.0 to 1.0 including."
  def random()
  defs random() :: float

  @doc "Round number to closest integer."
  def round(number)
  defs round(float) :: float
  defs round(float, integer) :: float

  @doc "Downcase string."
  def downcase(string)
  defs downcase(string) :: string

  @doc "Upcase string."
  def upcase(string)
  defs upcase(string) :: string

  @doc "Returns the current date and time."
  def now()
  defs now() :: datetime

  @doc "Returns the current local date and time."
  def localtimestamp()
  defs localtimestamp() :: datetime

  @doc "Extract date from datetime."
  def date(datetime)
  defs date(datetime) :: date

  @doc "Extract time from datetime."
  def time(datetime)
  defs time(datetime) :: time

  @doc "Create a datetime from a date and a time"
  def datetime(date, time)
  defs datetime(date, time) :: datetime

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
