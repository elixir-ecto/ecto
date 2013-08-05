defmodule Ecto.Query.API do
  use Ecto.Query.Typespec

  ## Types

  @doc """
  Docs for float.
  """
  deft float
  deft integer
  deft boolean
  deft binary
  deft list(var)
  deft nil

  defa number :: float | integer

  ## Operators

  def (+arg)
  defs (+integer) :: integer
  defs (+float)   :: float

  def (-arg)
  defs (-integer) :: integer
  defs (-float)   :: float

  def not(arg)
  defs not(boolean) :: boolean

  @doc """
  Adds two numbers together.
  """
  def left + right
  defs float + number    :: float
  defs number + float    :: float
  defs integer + integer :: integer

  def left - right
  defs float - number    :: float
  defs number - float    :: float
  defs integer - integer :: integer

  def left * right
  defs float * number    :: float
  defs number * float    :: float
  defs integer * integer :: integer

  def left / right
  defs number / number   :: float

  def left == right
  defs number == number :: boolean
  defs var == var       :: boolean
  defs nil == _         :: boolean
  defs _ == nil         :: boolean

  def left != right
  defs number != number :: boolean
  defs var != var       :: boolean
  defs nil != _         :: boolean
  defs _ != nil         :: boolean

  def left <= right
  defs number <= number :: boolean
  defs var <= var       :: boolean

  def left >= right
  defs number >= number :: boolean
  defs var >= var       :: boolean

  def left < right
  defs number < number :: boolean
  defs var < var       :: boolean

  def left > right
  defs number > number :: boolean
  defs var > var       :: boolean

  def left and right
  defs boolean and boolean :: boolean

  def left or right
  defs boolean or boolean :: boolean

  def left in right
  defs var in list(var) :: boolean

  def left .. right
  defs integer .. integer :: list(integer)

  def left <> right
  defs binary <> binary :: binary

  def left ++ right
  defs list(var) ++ list(var) :: list(var)

  ## Functions

  def pow(base, exp)
  defs pow(float, number) :: float
  defs pow(number, float) :: float
  defs pow(integer, integer) :: integer

  def div(left, right)
  defs div(integer, integer) :: integer

  def rem(left, right)
  defs rem(integer, integer) :: integer

  def random()
  defs random() :: float

  def round(number)
  defs round(float) :: float
  defs round(float, integer) :: float

  def downcase(string)
  defs downcase(binary) :: binary

  def upcase(string)
  defs upcase(binary) :: binary

  ## Aggregate functions

  @aggregate true
  def avg(numbers)
  defs avg(number) :: number

  @aggregate true
  def count(arg)
  defs count(_) :: integer

  @aggregate true
  def max(numbers)
  defs max(integer) :: integer
  defs max(float) :: float

  @aggregate true
  def min(numbers)
  defs min(integer) :: integer
  defs min(float) :: float

  @aggregate true
  def sum(numbers)
  defs sum(integer) :: integer
  defs sum(float) :: float
end
