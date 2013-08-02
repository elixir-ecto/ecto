defmodule Ecto.Query.API do
  use Ecto.Query.Typespec

  @doc """
  Docs for float.
  """
  deft float
  deft integer
  deft boolean
  deft list
  deft nil

  defa number :: float | integer

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
  defs float / number    :: float
  defs number / float    :: float
  defs integer / integer :: integer

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
  defs _ in list :: boolean

  def left .. right
  defs integer .. integer :: list
end
