defmodule Ecto.Query.SelectBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  # Escapes a select query to. Allows tuples, lists and variables at the top
  # level.

  # Tuple
  def escape({ left, right }, vars) do
    { escape(left, vars), escape(right, vars) }
  end

  # Tuple
  def escape({ :{}, _, list }, vars) do
    list = Enum.map(list, &escape(&1, vars))
    { :{}, [], [:{}, [], list] }
  end

  # List
  def escape(list, vars) when is_list(list) do
    Enum.map(list, &escape(&1, vars))
  end

  # var - where var is bound
  def escape({ var, _, context}, vars) when is_atom(var) and is_atom(context) do
    ix = Enum.find_index(vars, &(&1 == var))
    if ix do
      { :{}, [], [ :&, [], [ix] ] }
    else
      # TODO: This should raise
    end
  end

  def escape(other, vars) do
    BuilderUtil.escape(other, vars)
  end
end
