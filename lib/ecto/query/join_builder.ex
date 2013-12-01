defmodule Ecto.Query.JoinBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil
  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr
  alias Ecto.Query.AssocJoinExpr

  @doc """
  Escapes a join expression (not including the `on` expression).

  It returns a tuple containing if this join is an association join,
  binds and the expression. `binds` is either an empty list or a list
  of single. `expr` is either an alias or an association join of format
  `entity.field`.

  ## Examples

      iex> escape(quote(do: x in "foo"), [])
      { false, [:x], "foo" }

      iex> escape(quote(do: x in Sample), [])
      { false, [:x], { :__aliases__, [alias: false], [:Sample] } }

      iex> escape(quote(do: c in p.comments), [:p])
      {true, [:c], {:{}, [], [:., [], [{:{}, [], [:&, [], [0]]}, :comments]]}}

  """
  @spec escape(Macro.t, [atom]) :: { boolean, [atom], Macro.t }
  def escape({ :in, _, [{ var, _, context }, expr] }, vars)
      when is_atom(var) and is_atom(context) do
    escape(expr, vars) |> set_elem(1, [var])
  end

  def escape({ :in, _, [{ var, _, context }, expr] }, vars)
      when is_atom(var) and is_atom(context) do
    escape(expr, vars) |> set_elem(1, [var])
  end

  def escape({ :__aliases__, _, _ } = module, _vars) do
    { false, [], module }
  end

  def escape(string, _vars) when is_binary(string) do
    { false, [], string }
  end

  def escape(dot, vars) do
    case BuilderUtil.escape_dot(dot, vars) do
      { var, field } ->
        { true, [], { :{}, [], [:., [], [var, field]] } }
      :error ->
        raise Ecto.QueryError, reason: "malformed `join` query expression"
    end
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, atom, [Macro.t], Macro.t, Macro.t, Macro.Env.t) :: Macro.t
  def build(query, qual, binding, expr, on, env) do
    binding = BuilderUtil.escape_binding(binding)
    { is_assoc?, join_binding, join_expr } = escape(expr, binding)

    validate_qual(qual)
    validate_on(is_assoc?, on)

    if (bind = Enum.first(join_binding)) && bind in binding do
      raise Ecto.QueryError, reason: "variable `#{bind}` is already defined in query"
    end

    # Define the variable that will be used to calculate the number of binds.
    # If the variable is known at compile time, calculate it now.
    query = Macro.expand(query, env)
    { query, getter, setter } = count_binds(query, is_assoc?)

    join =
      if is_assoc? do
        quoted_assoc_join_expr(qual, join_expr, env)
      else
        on = on && BuilderUtil.escape(on, binding ++ join_binding, { bind, getter })
        quoted_join_expr(qual, join_expr, on, env)
      end

    case query do
      Query[joins: joins] ->
        query.joins(joins ++ [join]) |> BuilderUtil.escape_query
      _ ->
        quote do
          Query[joins: joins] = query = Ecto.Queryable.to_query(unquote(query))
          unquote(setter)
          query.joins(joins ++ [unquote(join)])
        end
    end
  end

  defp count_binds(query, is_assoc?) do
    case BuilderUtil.unescape_query(query) do
      # We have the query, calculate the count binds.
      Query[] = unescaped ->
        { unescaped, BuilderUtil.count_binds(unescaped), nil }

      # We don't have the query but we won't use it anyway.
      _  when is_assoc? ->
        { query, nil, nil }

      # We don't have the query nor can use it, handle it at runtime.
      _ ->
        { query,
          quote(do: var!(count_binds, Ecto.Query)),
          quote(do: var!(count_binds, Ecto.Query) = BuilderUtil.count_binds(query)) }
    end
  end

  defp quoted_join_expr(qual, join_expr, on_expr, env) do
    quote do
      on = QueryExpr[expr: unquote(on_expr), line: unquote(env.line), file: unquote(env.file)]
      JoinExpr[qual: unquote(qual), source: unquote(join_expr), on: on,
               file: unquote(env.file), line: unquote(env.line)]
    end
  end

  defp quoted_assoc_join_expr(qual, join_expr, env) do
    quote do
      AssocJoinExpr[qual: unquote(qual), expr: unquote(join_expr),
                    file: unquote(env.file), line: unquote(env.line)]
    end
  end

  @qualifiers [ :inner, :left, :right, :full ]

  defp validate_qual(qual) when qual in @qualifiers, do: :ok
  defp validate_qual(_qual) do
    raise Ecto.QueryError,
      reason: "invalid join qualifier, accepted qualifiers are: " <>
              Enum.map_join(@qualifiers, ", ", &"`#{inspect &1}`")
  end

  defp validate_on(is_assoc?, on) when is_assoc? == nil?(on), do: :ok
  defp validate_on(_, _) do
    raise Ecto.QueryError,
      reason: "`join` expression requires explicit `on` " <>
              "expression unless association join expression"
  end
end
