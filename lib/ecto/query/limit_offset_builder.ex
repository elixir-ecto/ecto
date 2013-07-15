defmodule Ecto.Query.LimitOffsetBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  def escape(expr, vars) do
    case BuilderUtil.find_vars(expr, vars) do
      nil -> expr
      var ->
        reason = "bound vars, `#{var}`, are not allowed in limit and offset queries"
        raise Ecto.InvalidQuery, reason: reason
    end
  end
end
