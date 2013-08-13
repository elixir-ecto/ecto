defmodule Ecto.Query.OrderByBuilder do
  @moduledoc false

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

    ix = Enum.find_index(vars, &(&1 == var))
    if var == :_ or nil?(ix) do
      raise Ecto.InvalidQuery, reason: "unbound variable `#{var}` in query"
    end

    unless dir in [nil, :asc, :desc] do
      reason = "non-allowed direction `#{dir}`, only `asc` and `desc` allowed"
      raise Ecto.InvalidQuery, reason: reason
    end

    var = { :&, [], [ix] }
    Macro.escape({ dir, var, field })
  end

  defp escape_field({ dir, { { :., _, _ } = dot, _, [] } }, vars) do
    escape_field({ dir, dot }, vars)
  end

  defp escape_field({ { :., _, _ } = dot, _, [] }, vars) do
    escape_field(dot, vars)
  end

  defp escape_field({ :., _, _ } = ast, vars) do
    escape_field({ nil, ast }, vars)
  end

  defp escape_field(_other, _vars) do
    raise Ecto.InvalidQuery, reason: "malformed order_by query"
  end
end
