defmodule Ecto.Query.WhereBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  # Escapes a where expression, see `BuilderUtil.escape`
  def escape(ast, vars, join_var // nil) do
    BuilderUtil.escape(ast, vars, join_var)
  end
end
