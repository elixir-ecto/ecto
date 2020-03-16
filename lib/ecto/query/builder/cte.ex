import Kernel, except: [apply: 3]

defmodule Ecto.Query.Builder.CTE do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes the CTE name.

      iex> escape(quote do: "FOO")
      "FOO"
  """
  @spec escape(Macro.t) :: Macro.t
  def escape(name) when is_bitstring(name), do: name

  def escape({:^, _, [expr]}), do: expr

  def escape(other) do
    Builder.error! "`#{Macro.to_string(other)}` is not a valid CTE name. " <>
                   "It must be a literal string or an interpolated variable."
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, Macro.t, Macro.t, Macro.Env.t) :: Macro.t
  def build(query, name, cte, env) do
    Builder.apply_query(query, __MODULE__, [escape(name), build_cte(name, cte, env)], env)
  end

  @spec build_cte(Macro.t, Macro.t, Macro.t) :: Macro.t
  def build_cte(_name, {:^, _, [expr]}, _env) do
    quote do: Ecto.Queryable.to_query(unquote(expr))
  end

  def build_cte(_name, {:fragment, _, _} = fragment, env) do
    {expr, {params, :acc}} = Builder.escape(fragment, :any, {[], :acc}, [], env)
    params = Builder.escape_params(params)

    quote do
      %Ecto.Query.QueryExpr{
        expr: unquote(expr),
        params: unquote(params),
        file: unquote(env.file),
        line: unquote(env.line)
      }
    end
  end

  def build_cte(name, cte, _env) do
    Builder.error! "`#{Macro.to_string(cte)}` is not a valid CTE (named: #{Macro.to_string(name)}). " <>
                   "The CTE must be an interpolated query, such as ^existing_query or a fragment."
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, bitstring, Ecto.Queryable.t) :: Ecto.Query.t
  def apply(%Ecto.Query{with_ctes: with_expr} = query, name, with_query) do
    with_expr = with_expr || %Ecto.Query.WithExpr{}
    queries = List.keystore(with_expr.queries, name, 0, {name, with_query})
    with_expr = %{with_expr | queries: queries}
    %{query | with_ctes: with_expr}
  end

  def apply(query, name, with_query) do
    apply(Ecto.Queryable.to_query(query), name, with_query)
  end
end
