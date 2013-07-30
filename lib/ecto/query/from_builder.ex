defmodule Ecto.Query.FromBuilder do
  @moduledoc false

  # There are two kinds of from expressions:
  # * An elixir expression that evaluates to a Queryable, that is used to
  #   extend queries. Variables in the Queryable can optionally be rebound
  #   with an `in` expression. Examples:
  #   - `expr`
  #   - `var in query`
  #   - `[var1, var2] in query`.
  #
  # * A single entity, can optionally be bound to a variable. This is the
  #   only kind of `from` expression that is allowed inside a query. Examples:
  #   - `Entity`
  #   - `var in Entity

  # Returns `{ bindings, quoted_expr }`

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

  # Every Entity must have a matching bound to a variable, otherwise zipping
  # of bindings and entities will fail because every entity doesn't have a
  # matching variable
  # `Entity` == `_ in Entity`
  def escape({ :__aliases__, _, _ } = expr) do
    { [:_], expr }
  end

  def escape(expr) do
    { [], expr }
  end

  # Checks if an expression matches the second kind of `from` expression
  def validate_query_from(quoted) do
    unless is_query_from(quoted) do
      raise Ecto.InvalidQuery, reason: "invalid `from` expression, expected " <>
        "format: `var in Entity` or `Entity`"
    end
  end

  defp is_query_from({ :in, _, [{ var, _, context }, { :__aliases__, _, _ }] })
      when is_atom(var) and is_atom(context), do: true
  defp is_query_from({ :__aliases__, _, _ }), do: true
  defp is_query_from(_), do: false
end
