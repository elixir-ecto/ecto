import Kernel, except: [apply: 3]

defmodule Ecto.Query.Builder.CTE do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes the CTE name.

      iex> escape(quote(do: "FOO"), __ENV__)
      "FOO"

  """
  @spec escape(Macro.t, Macro.Env.t) :: Macro.t
  def escape(name, _env) when is_bitstring(name), do: name

  def escape({:^, _, [expr]}, _env), do: expr

  def escape(expr, env) do
    case Macro.expand_once(expr, env) do
      ^expr ->
        Builder.error! "`#{Macro.to_string(expr)}` is not a valid CTE name. " <>
                       "It must be a literal string or an interpolated variable."

      expr ->
        escape(expr, env)
    end
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, Macro.t, Macro.t, Macro.Env.t) :: Macro.t
  def build(query, name, cte, env) do
    Builder.apply_query(query, __MODULE__, [escape(name, env), build_cte(name, cte, env)], env)
  end

  @spec build_cte(Macro.t, Macro.t, Macro.Env.t) :: Macro.t
  def build_cte(_name, {:^, _, [expr]}, _env) do
    quote do: Ecto.Queryable.to_query(unquote(expr))
  end

  def build_cte(_name, {:fragment, _, _} = fragment, env) do
    {expr, {params, _acc}} = Builder.escape(fragment, :any, {[], %{}}, [], env)
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

  def build_cte(name, cte, env) do
    case Macro.expand_once(cte, env) do
      ^cte ->
        Builder.error! "`#{Macro.to_string(cte)}` is not a valid CTE (named: #{Macro.to_string(name)}). " <>
                       "The CTE must be an interpolated query, such as ^existing_query or a fragment."

      cte ->
        build_cte(name, cte, env)
    end
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, bitstring, Ecto.Queryable.t) :: Ecto.Query.t
  # Runtime
  def apply(%Ecto.Query{with_ctes: with_expr} = query, name, %_{} = with_query) do
    %{query | with_ctes: apply_cte(with_expr, name, with_query)}
  end

  # Compile
  def apply(%Ecto.Query{with_ctes: with_expr} = query, name, with_query) do
    update = quote do
      Ecto.Query.Builder.CTE.apply_cte(unquote(with_expr), unquote(name), unquote(with_query))
    end

    %{query | with_ctes: update}
  end

  # Runtime catch-all
  def apply(query, name, with_query) do
    apply(Ecto.Queryable.to_query(query), name, with_query)
  end

  @doc false
  def apply_cte(nil, name, with_query) do
    %Ecto.Query.WithExpr{queries: [{name, with_query}]}
  end

  def apply_cte(%Ecto.Query.WithExpr{queries: queries} = with_expr, name, with_query) do
    %{with_expr | queries: List.keystore(queries, name, 0, {name, with_query})}
  end
end
