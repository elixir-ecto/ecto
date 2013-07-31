defmodule Ecto.Query.HavingBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  # Escapes a having expression, see `BuilderUtil.escape`
  def escape(ast, vars) do
    BuilderUtil.escape(ast, vars)
  end
end
