defmodule Ecto.Query.WhereBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  # Escapes a where expression, see `BuilderUtil.escape`
  def escape(ast, vars) do
    BuilderUtil.escape(ast, vars)
  end
end
