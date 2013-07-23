defmodule Ecto.Query.FromBuilder do
  @moduledoc false

  # Accepts the following expressions: `expr`, `bind in expr` and
  # `[binds...] in expr`
  # Returns `{ bindings, expr }`

  def escape({ :in, _, [list, expr] }) when is_list(list) do
    binds = Enum.map(list, fn
      { var, _, context } when is_atom(var) and is_atom(context) ->
        var
      _ ->
        raise Ecto.InvalidQuery, reason: "invalid `from` query expression"
    end)
    { binds, expr }
  end

  def escape({ :in, meta, [var, expr] }) do
    escape({ :in, meta, [[var], expr] })
  end

  def escape(expr) do
    { [], expr }
  end
end
