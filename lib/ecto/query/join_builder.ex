defmodule Ecto.Query.JoinBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr

  @doc """
  Escapes a join expression (not including the `on` expression).

  It returns a tuple containing the binds, the on expression (if available)
  and the association expression.

  ## Examples

      iex> escape(quote(do: x in "foo"), [])
      {:x, "foo", nil}

      iex> escape(quote(do: "foo"), [])
      {nil, "foo", nil}

      iex> escape(quote(do: x in Sample), [])
      {:x, {:__aliases__, [alias: false], [:Sample]}, nil}

      iex> escape(quote(do: c in p.comments), [p: 0])
      {:c, nil, {{:{}, [], [:&, [], [0]]}, :comments}}

  """
  @spec escape(Macro.t, Keyword.t) :: {[atom], Macro.t | nil, Macro.t | nil}
  def escape({:in, _, [{var, _, context}, expr]}, vars)
      when is_atom(var) and is_atom(context) do
    {_, expr, assoc} = escape(expr, vars)
    {var, expr, assoc}
  end

  def escape({:in, _, [{var, _, context}, expr]}, vars)
      when is_atom(var) and is_atom(context) do
    {_, expr, assoc} = escape(expr, vars)
    {var, expr, assoc}
  end

  def escape({:__aliases__, _, _} = module, _vars) do
    {nil, module, nil}
  end

  def escape(string, _vars) when is_binary(string) do
    {nil, string, nil}
  end

  def escape(dot, vars) do
    case BuilderUtil.escape_dot(dot, vars) do
      {_, _} = var_field ->
        {[], nil, var_field}
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
  @spec build_with_binds(Macro.t, atom, [Macro.t], Macro.t, Macro.t, Macro.t, Macro.Env.t) :: {Macro.t, Keyword.t, non_neg_integer | nil}
  def build_with_binds(query, qual, binding, expr, on, count_bind, env) do
    binding = BuilderUtil.escape_binding(binding)
    {join_bind, join_expr, join_assoc} = escape(expr, binding)
    is_assoc? = not nil?(join_assoc)

    validate_qual(qual)
    validate_on(on, is_assoc?)
    validate_bind(join_bind, binding)

    if join_bind && !count_bind do
      # If count_bind is not an integer, make it a variable.
      # The variable is the getter/setter storage.
      count_bind = quote(do: count_bind)
      count_setter = quote(do: unquote(count_bind) = BuilderUtil.count_binds(query))
    end

    binding = binding ++ [{join_bind, count_bind}]

    join_on = escape_on(on, binding, env)
    join =
      quote do
        %JoinExpr{qual: unquote(qual), source: unquote(join_expr), on: unquote(join_on),
                  file: unquote(env.file), line: unquote(env.line), assoc: unquote(join_assoc)}
      end

    if is_integer(count_bind) do
      count_bind = count_bind + 1
      quoted = BuilderUtil.apply_query(query, __MODULE__, [join], env)
    else
      count_bind = quote(do: unquote(count_bind) + 1)
      quoted =
        quote do
          query = Ecto.Queryable.to_query(unquote(query))
          unquote(count_setter)
          %{query | joins: query.joins ++ [unquote(join)]}
        end
      end

    {quoted, binding, count_bind}
  end

  def apply(query, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | joins: query.joins ++ [expr]}
  end

  defp escape_on(nil, _binding, _env), do: nil
  defp escape_on(on, binding, env) do
    on = BuilderUtil.escape(on, binding)
    quote do: %QueryExpr{expr: unquote(on), line: unquote(env.line), file: unquote(env.file)}
  end

  @qualifiers [:inner, :left, :right, :full]

  defp validate_qual(qual) when qual in @qualifiers, do: :ok
  defp validate_qual(_qual) do
    raise Ecto.QueryError,
      reason: "invalid join qualifier, accepted qualifiers are: " <>
              Enum.map_join(@qualifiers, ", ", &"`#{inspect &1}`")
  end

  defp validate_on(nil, false) do
    raise Ecto.QueryError,
      reason: "`join` expression requires explicit `on` " <>
              "expression unless it's an association join expression"
  end
  defp validate_on(_on, _is_assoc?), do: :ok

  defp validate_bind(bind, all) do
    if bind && bind in all do
      raise Ecto.QueryError, reason: "variable `#{bind}` is already defined in query"
    end
  end
end
