defmodule Ecto.Query.OrderByBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  # Escapes an order by query to a list of `{ direction, field }` pairs. See
  # `Ecto.Query.order_by for the allowed formats for the expression.

  def escape(list, vars) when is_list(list) do
    Enum.map(list, &escape_field(&1, vars))
  end

  def escape(field, vars) do
    [ escape_field(field, vars) ]
  end

  defp escape_field({ dir, { :., _, [{ var, _, context }, field] } }, vars)
      when is_atom(var) and is_atom(context) and is_atom(field) do
    check_dir(dir)
    var_escaped = BuilderUtil.escape_var(var, vars)
    { :{}, [], [dir, var_escaped, Macro.escape(field)] }
  end

  defp escape_field({ dir, { :field, _, [{ var, _, context }, field] } }, vars)
      when is_atom(var) and is_atom(context) do
    check_dir(dir)
    var_escaped = BuilderUtil.escape_var(var, vars)
    field_escaped = BuilderUtil.escape(field, vars)
    { :{}, [], [dir, var_escaped, field_escaped] }
  end

  defp escape_field({ dir, { { :., _, _ } = dot, _, [] } }, vars) do
    escape_field({ dir, dot }, vars)
  end

  defp escape_field({ _, _ }, _vars) do
    raise Ecto.QueryError, reason: "malformed order_by query"
  end

  defp escape_field(ast, vars) do
    escape_field({ nil, ast }, vars)
  end

  defp check_dir(dir) do
    unless dir in [nil, :asc, :desc] do
      reason = "non-allowed direction `#{dir}`, only `asc` and `desc` allowed"
      raise Ecto.QueryError, reason: reason
    end
  end
end
