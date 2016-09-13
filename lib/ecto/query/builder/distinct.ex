import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Distinct do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes a list of quoted expressions.

      iex> escape(quote do true end, [], __ENV__)
      {true, %{}}

      iex> escape(quote do [x.x, 13] end, [x: 0], __ENV__)
      {[asc: {:{}, [], [{:{}, [], [:., [], [{:{}, [], [:&, [], [0]]}, :x]]}, [], []]},
        asc: 13],
       %{}}

  """
  @spec escape(Macro.t, Keyword.t, Macro.Env.t) :: {Macro.t, %{}}
  def escape(expr, _vars, _env) when is_boolean(expr) do
    {expr, %{}}
  end

  def escape({:^, _, [expr]}, _vars, _env) do
    {quote(do: Ecto.Query.Builder.Distinct.distinct!(unquote(expr))), %{}}
  end

  def escape(expr, vars, env) do
    Ecto.Query.Builder.OrderBy.escape(:distinct, expr, vars, env)
  end

  @doc """
  Called at runtime to verify distinct.
  """
  def distinct!(distinct) when is_boolean(distinct) do
    distinct
  end
  def distinct!(distinct) do
    Ecto.Query.Builder.OrderBy.order_by!(:distinct, distinct)
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(query, binding, expr, env) do
    {query, binding} = Builder.escape_binding(query, binding)
    {expr, params} = escape(expr, binding, env)
    params = Builder.escape_params(params)

    distinct = quote do: %Ecto.Query.QueryExpr{
                           expr: unquote(expr),
                           params: unquote(params),
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
