defmodule Ecto.Query.LimitOffsetBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  # Validates the expression, raising if it isn't an integer value
  def validate(expr) when is_integer(expr), do: :ok

  def validate(_expr) do
    raise Ecto.InvalidQuery, reason: "limit and offset expressions must be a single integer value"
  end
end
