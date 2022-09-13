import Kernel, except: [apply: 3]

defmodule Ecto.Query.Builder.LimitOffset do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(:limit | :offset, Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(type, query, binding, expr, env) do
    {query, binding} = Builder.escape_binding(query, binding, env)
    {expr, {params, _acc}} = Builder.escape(expr, :integer, {[], %{}}, binding, env)
    params = Builder.escape_params(params)

    if contains_variable?(expr) do
      Builder.error! "query variables are not allowed in #{type} expression"
    end

    limoff = quote do: %Ecto.Query.QueryExpr{
                        expr: unquote(expr),
                        params: unquote(params),
                        file: unquote(env.file),
                        line: unquote(env.line)}

    Builder.apply_query(query, __MODULE__, [type, limoff], env)
  end

  defp contains_variable?(ast) do
    ast
    |> Macro.prewalk(false, fn
         {:&, _, [_]} = expr, _ -> {expr, true}
         expr, acc -> {expr, acc}
       end)
    |> elem(1)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, :limit | :offset, term) :: Ecto.Query.t
  def apply(%Ecto.Query{} = query, :limit, expr) do
    %{query | limit: expr}
  end
  def apply(%Ecto.Query{} = query, :offset, expr) do
    %{query | offset: expr}
  end
  def apply(query, kind, expr) do
    apply(Ecto.Queryable.to_query(query), kind, expr)
  end
end
