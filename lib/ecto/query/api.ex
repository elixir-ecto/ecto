defmodule Ecto.Query.API do
  use Ecto.Query.Typespec

  ## Types

  deft float
  deft integer
  deft boolean
  deft binary
  deft string
  deft list(var)
  deft datetime
  deft interval
  deft nil

  defa number :: float | integer

  ## Operators

  @doc "Positive number."
  def (+arg)
  defs (+integer) :: integer
  defs (+float)   :: float

  @doc "Negate number."
  def (-arg)
  defs (-integer) :: integer
  defs (-float)   :: float

  @doc "Boolean not."
  def not(arg)
  defs not(boolean) :: boolean

  @doc "Addition of numbers."
  def left + right
  defs float + number      :: float
  defs number + float      :: float
  defs integer + integer   :: integer

  @doc "Subtraction of numbers."
  def left - right
  defs float - number      :: float
  defs number - float      :: float
  defs integer - integer   :: integer

  @doc "Multiplication of numbers."
  def left * right
  defs float * number    :: float
  defs number * float    :: float
  defs integer * integer :: integer

  @doc "Division of numbers."
  def left / right
  defs number / number   :: float

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
  Return `true` if `left` is in `right` list, `false`
  otherwise.
  """
  def left in right
  defs var in list(var) :: boolean

  @doc "Range from left to right."
  def left .. right
  defs integer .. integer :: list(integer)

  @doc "Binary and string concatenation."
  def left <> right
  defs binary <> binary :: binary
  defs string <> string :: string

  @doc "List concatenation."
  def left ++ right
  defs list(var) ++ list(var) :: list(var)

  ## Functions

  @doc """
  Casts a binary literal to a binary type. By default a
  binary literal is of the string type.
  """
  def binary(binary)
  defs binary(binary) :: binary
  defs binary(string) :: binary

  @doc "Addition of datetime's with interval's"
  def date_add(left, right)
  defs date_add(datetime, interval) :: datetime
  defs date_add(interval, datetime) :: datetime
  defs date_add(interval, interval) :: interval

  @doc "Subtraction of datetime's with interval's"
  def date_sub(left, right)
  defs date_sub(datetime, interval) :: datetime
  defs date_sub(interval, datetime) :: datetime
  defs date_sub(interval, interval) :: interval

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

  @doc "Returns the current date and time"
  def now()
  defs now() :: datetime

  def localtimestamp()
  defs localtimestamp() :: datetime

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

  @doc """
  Aggregate function, the minimum number of the given field in the current
  group.
  """
  @aggregate true
  def min(numbers)
  defs min(integer) :: integer
  defs min(float) :: float

  @doc "Aggregate function, sums the given field over the current group."
  @aggregate true
  def sum(numbers)
  defs sum(integer) :: integer
  defs sum(float) :: float
end
