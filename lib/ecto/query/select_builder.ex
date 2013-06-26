defmodule Ecto.Query.SelectBuilder do
  @moduledoc false

  def escape({ left, right }, vars) do
    { :tuple, [sub_escape(left, vars), sub_escape(right, vars)] }
  end

  def escape({ :{}, _, list }, vars) do
    { :tuple, Enum.map(list, sub_escape(&1, vars)) }
  end

  def escape({ :__block__, _, [ast] }, vars) do
    escape(ast, vars)
  end

  def escape(list, vars) when is_list(list) do
    { :list, Enum.map(list, sub_escape(&1, vars)) }
  end

  def escape(other, vars) do
    { :single, sub_escape(other, vars) }
  end

   # var.x - where var is bound
  defp sub_escape({ { :., meta2, [{var, _, context} = left, right] }, meta, [] }, vars) do
    if { var, context } in vars do
      left_escaped = { :{}, [], tuple_to_list(left) }
      dot_escaped = { :{}, [], [:., meta2, [left_escaped, right]] }
      { :{}, meta, [dot_escaped, meta, []] }
    else
      do_raise()
    end
  end

  defp sub_escape(_other, _vars), do: do_raise()

  defp do_raise() do
    raise ArgumentError, message: "only dotted expressions of bound vars are allowed `bound.field`"
  end
end
