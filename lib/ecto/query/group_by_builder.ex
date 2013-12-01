defmodule Ecto.Query.GroupByBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  # Escapes a group by query to a list of fields

  def escape(list, vars) when is_list(list) do
    Enum.map(list, &escape_field(&1, vars))
  end

  def escape({ var, _, context }, vars) when is_atom(var) and is_atom(context) do
    BuilderUtil.escape_var(var, vars)
  end

  def escape(field, vars) do
    [escape_field(field, vars)]
  end

  defp escape_field(dot, vars) do
    case BuilderUtil.escape_dot(dot, vars) do
      { _, _ } = var_field ->
        var_field
      :error ->
        raise Ecto.QueryError, reason: "malformed `group_by` query expression"
    end
  end
end
