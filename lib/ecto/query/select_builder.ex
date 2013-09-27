defmodule Ecto.Query.SelectBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  # Escapes a select query to. Allows tuples, lists and variables at the top
  # level or a single `assoc(x, y)` expression.

  def escape({ :assoc, _, [{ fst, _, fst_ctxt }, { snd, _, snd_ctxt }] }, vars)
      when is_atom(fst) and is_atom(fst_ctxt) and is_atom(snd) and is_atom(snd_ctxt) do
    fst = BuilderUtil.escape_var(fst, vars)
    snd = BuilderUtil.escape_var(snd, vars)
    { :{}, [], [:assoc, [], [fst, snd]] }
  end

  def escape(other, vars), do: do_escape(other, vars)

  # Tuple
  defp do_escape({ left, right }, vars) do
    do_escape({ :{}, [], [left, right] }, vars)
  end

  # Tuple
  defp do_escape({ :{}, _, list }, vars) do
    list = Enum.map(list, &do_escape(&1, vars))
    { :{}, [], [:{}, [], list] }
  end

  # List
  defp do_escape(list, vars) when is_list(list) do
    Enum.map(list, &do_escape(&1, vars))
  end

  # var - where var is bound
  defp do_escape({ var, _, context}, vars) when is_atom(var) and is_atom(context) do
    BuilderUtil.escape_var(var, vars)
  end

  defp do_escape(other, vars) do
    BuilderUtil.escape(other, vars)
  end
end
