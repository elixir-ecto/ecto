import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Distinct do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes a list of quoted expressions.

      iex> escape(quote do true end, {[], %{}}, [], __ENV__)
      {true, {[], %{}}}

      iex> escape(quote do [x.x, 13] end, {[], %{}}, [x: 0], __ENV__)
      {[asc: {:{}, [], [{:{}, [], [:., [], [{:{}, [], [:&, [], [0]]}, :x]]}, [], []]},
        asc: 13],
       {[], %{}}}

  """
  @spec escape(Macro.t, {list, term}, Keyword.t, Macro.Env.t) :: {Macro.t, {list, term}}
  def escape(expr, params_acc, _vars, _env) when is_boolean(expr) do
    {expr, params_acc}
  end

  def escape(expr, params_acc, vars, env) do
    Builder.OrderBy.escape(:distinct, expr, params_acc, vars, env)
  end

  @doc """
  Called at runtime to verify distinct.
  """
  def distinct!(query, distinct, file, line) when is_boolean(distinct) do
    apply(query, %Ecto.Query.ByExpr{expr: distinct, params: [], line: line, file: file})
  end
  def distinct!(query, distinct, file, line) do
    {expr, params, subqueries} =
      Builder.OrderBy.order_by_or_distinct!(:distinct, query, distinct, [])

    expr = %Ecto.Query.ByExpr{
      expr: expr,
      params: Enum.reverse(params),
      line: line,
      file: file,
      subqueries: subqueries
    }

    apply(query, expr)
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(query, _binding, {:^, _, [var]}, env) do
    quote do
      Ecto.Query.Builder.Distinct.distinct!(unquote(query), unquote(var), unquote(env.file), unquote(env.line))
    end
  end

  def build(query, binding, expr, env) do
    {query, binding} = Builder.escape_binding(query, binding, env)
    {expr, {params, acc}} = escape(expr, {[], %{subqueries: []}}, binding, env)
    params = Builder.escape_params(params)

    distinct = quote do: %Ecto.Query.ByExpr{
                           expr: unquote(expr),
                           params: unquote(params),
                           subqueries: unquote(acc.subqueries),
                           file: unquote(env.file),
                           line: unquote(env.line)}
    Builder.apply_query(query, __MODULE__, [distinct], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.t
  def apply(%Ecto.Query{distinct: nil} = query, expr) do
    %{query | distinct: expr}
  end
  def apply(%Ecto.Query{}, _expr) do
    Builder.error! "only one distinct expression is allowed in query"
  end
  def apply(query, expr) do
    apply(Ecto.Queryable.to_query(query), expr)
  end
end
