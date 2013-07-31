defmodule Ecto.Query.GroupByBuilder do
  @moduledoc false

  # Escapes a group by query to a list of fields

  def escape(list, vars) when is_list(list) do
    Enum.map(list, escape_field(&1, vars))
  end

  def escape(field, vars) do
    [ escape_field(field, vars) ]
  end

  defp escape_field({ { :., _, _ } = dot, _, [] }, vars) do
    escape_field(dot, vars)
  end

  defp escape_field({ :., _, [{ var, _, context }, field] }, vars)
      when is_atom(var) and is_atom(context) and is_atom(field) do

    unless var in vars do
      raise Ecto.InvalidQuery, reason: "unbound variable `#{var}` in query"
    end
    { var, field }
  end

  defp escape_field(_other, _vars) do
    raise Ecto.InvalidQuery, reason: "malformed group_by query"
  end
end
