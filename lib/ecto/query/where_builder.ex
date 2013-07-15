defmodule Ecto.Query.WhereBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  def escape(ast, vars) do
    BuilderUtil.escape(ast, vars)
  end
end
