defmodule Ecto.Query.Builder.Update do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes a list of quoted expressions.

      iex> escape([], [], __ENV__)
      {[], %{}}

      iex> escape([set: []], [], __ENV__)
      {[set: []], %{}}

      iex> escape([set: [foo: 1]], [], __ENV__)
      {[set: [foo: 1]], %{}}

      iex> escape(quote(do: [set: [foo: ^1]]), [], __ENV__)
      {[set: [foo: {:{}, [], [:^, [], [0]]}]], %{0 => {1, {0, :foo}}}}

  """
  @spec escape(Macro.t, Keyword.t, Macro.Env.t) :: {Macro.t, %{}}
  def escape(expr, vars, env) when is_list(expr) do
    Enum.map_reduce expr, %{}, fn
      {k, v}, acc when is_atom(k) and is_list(v) ->
        {v, params} = escape_each(k, v, acc, vars, env)
        {{k, v}, params}
      _, _acc ->
        error! expr
    end
  end

  def escape(expr, _vars, _env) do
    error! expr
  end

  defp escape_each(key, kw, params, vars, env) do
    Enum.map_reduce kw, params, fn
      {k, v}, acc when is_atom(k) ->
        {v, params} = Builder.escape(v, {0, k}, acc, vars, env)
        {{k, v}, params}
      _, _acc ->
        Builder.error! "malformed #{inspect key} in update `#{Macro.to_string(kw)}`, " <>
                       "expected a keyword list"
    end
  end

  defp error!(expr) do
    Builder.error! "malformed update `#{Macro.to_string(expr)}` in query expression, " <>
                   "expected a keyword list with lists as values"
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(query, binding, expr, env) do
    binding        = Builder.escape_binding(binding)
    {expr, params} = escape(expr, binding, env)
    params         = Builder.escape_params(params)

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
  def apply(query, updates) do
    query = Ecto.Queryable.to_query(query)
    %{query | updates: [updates|query.updates]}
  end
end
