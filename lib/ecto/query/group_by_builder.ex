defmodule Ecto.Query.GroupByBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  @doc """
  Escapes a list of quoted expressions.

  See `Ecto.BuilderUtil.escape/2`.

      iex> escape(quote do [x.x, foo()] end, [x: 0])
      [{:{}, [], [{:{}, [], [:., [], [{:{}, [], [:&, [], [0]]}, :x]]}, [], []]},
       {:{}, [], [:foo, [], []]}]
  """
  @spec escape(Macro.t, Keyword.t) :: Macro.t
  def escape(expr, vars) do
    List.wrap(expr)
    |> BuilderUtil.escape(vars)
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(query, binding, expr, env) do
    binding  = BuilderUtil.escape_binding(binding)
    expr     = escape(expr, binding)
    group_by = quote do: %Ecto.Query.QueryExpr{expr: unquote(expr),
                         file: unquote(env.file), line: unquote(env.line)}
    BuilderUtil.apply_query(query, __MODULE__, [group_by], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.t
  def apply(query, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | group_bys: query.group_bys ++ [expr]}
  end
end
