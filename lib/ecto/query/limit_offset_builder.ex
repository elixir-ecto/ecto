defmodule Ecto.Query.LimitOffsetBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  # No escaping, only check if a bound var is used.
  def escape(expr, vars) do
    case BuilderUtil.find_vars(expr, vars) do
      nil -> expr
      var ->
        reason = "bound vars, `#{var}`, are not allowed in limit and offset queries"
        raise Ecto.InvalidQuery, reason: reason
    end
  end

  # Validates the expression, raising if it isn't an integer value
  def validate(expr) when is_integer(expr), do: :ok

  def validate(_expr) do
    raise Ecto.InvalidQuery, reason: "limit and offset expressions must be a single integer value"
  end
end
