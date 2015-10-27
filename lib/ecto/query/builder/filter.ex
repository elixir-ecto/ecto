defmodule Ecto.Query.Builder.Filter do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(:where | :having, Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(kind, query, binding, expr, env) do
    binding        = Builder.escape_binding(binding)
    {expr, params} = escape(kind, expr, binding, env)
    params         = Builder.escape_params(params)

    expr = quote do: %Ecto.Query.QueryExpr{
                        expr: unquote(expr),
                        params: unquote(params),
                        file: unquote(env.file),
                        line: unquote(env.line)}
    Builder.apply_query(query, __MODULE__, [kind, expr], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, :where | :having, term) :: Ecto.Query.t
  def apply(query, _, %{expr: true}) do
    query
  end

  def apply(query, :where, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | wheres: query.wheres ++ [expr]}
  end

  def apply(query, :having, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | havings: query.havings ++ [expr]}
  end

  @doc """
  Escapes a where or having clause.

  It allows query expressions that evaluate to a boolean
  or a keyword list of field names and values. In a keyword
  list multiple key value pairs will be joined with "and".
  """
  @spec escape(:where | :having, Macro.t, Keyword.t, Macro.Env.t) :: {Macro.t, %{}}
  def escape(kind, {:^, _, [var]}, _, _)  when is_tuple(var) do
    {quote(do: Ecto.Query.Builder.Filter.runtime!(unquote(kind), unquote(var))), %{}}
  end

  def escape(_kind, [], _vars, _env) do
    {true, %{}}
  end

  def escape(kind, expr, vars, env) when is_list(expr) do
    {parts, params} =
      Enum.map_reduce(expr, %{}, fn
        {field, value}, acc when is_atom(field) ->
          {value, params} = Builder.escape(value, {0, field}, acc, vars, env)
          {{:{}, [], [:==, [], [to_escaped_field(field), value]]}, params}
        _, _acc ->
          Builder.error! "expected a keyword list at compile time in #{kind}, " <>
                         "got: `#{Macro.to_string expr}`. If you would like to " <>
                         "pass a list dynamically, please interpolate the whole list with ^"
      end)

    expr = Enum.reduce parts, &{:{}, [], [:and, [], [&2, &1]]}
    {expr, params}
  end

  def escape(_kind, expr, vars, env) do
    Builder.escape(expr, :boolean, %{}, vars, env)
  end

  def runtime!(_kind, []) do
    true
  end

  def runtime!(kind, params) when is_list(params) do
    params
      |> Enum.map(fn
        {field, value} when is_atom(field) ->
          value = %Ecto.Query.Tagged{tag: nil, type: {0, field}, value: value}
          {:==, [], [to_field(field), value]}
        {_, _} ->
          raise ArgumentError, "expected a keyword list in #{kind}, got: `#{inspect params}`"
      end)
     |> Enum.reduce &{:and, [], [&2, &1]}
  end

  defp to_escaped_field(field), do: Macro.escape to_field(field) 
  defp to_field(field), do: {{:., [], [{:&, [], [0]}, field]}, [], []}
end
