import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.OrderBy do
  @moduledoc false

  alias Ecto.Query.Builder

  @directions [
    :asc,
    :asc_nulls_last,
    :asc_nulls_first,
    :desc,
    :desc_nulls_last,
    :desc_nulls_first
  ]

  @doc """
  Escapes an order by query.

  The query is escaped to a list of `{direction, expression}`
  pairs at runtime. Escaping also validates direction is one of
  `:asc`, `:asc_nulls_last`, `:asc_nulls_first`, `:desc`,
  `:desc_nulls_last` or `:desc_nulls_first`.

  ## Examples

      iex> escape(:order_by, quote do [x.x, desc: 13] end, {[], :acc}, [x: 0], __ENV__)
      {[asc: {:{}, [], [{:{}, [], [:., [], [{:{}, [], [:&, [], [0]]}, :x]]}, [], []]},
        desc: 13],
       {[], :acc}}

  """
  @spec escape(:order_by | :distinct, Macro.t, {list, term}, Keyword.t, Macro.Env.t) ::
          {Macro.t, {list, term}}
  def escape(kind, {:^, _, [expr]}, params_acc, _vars, _env) do
    {quote(do: Ecto.Query.Builder.OrderBy.order_by!(unquote(kind), unquote(expr))), params_acc}
  end

  def escape(kind, expr, params_acc, vars, env) do
    expr
    |> List.wrap
    |> Enum.map_reduce(params_acc, &do_escape(&1, &2, kind, vars, env))
  end

  defp do_escape({dir, {:^, _, [expr]}}, params_acc, kind, _vars, _env) do
    {{quoted_dir!(kind, dir), quote(do: Ecto.Query.Builder.OrderBy.field!(unquote(kind), unquote(expr)))}, params_acc}
  end

  defp do_escape({:^, _, [expr]}, params_acc, kind, _vars, _env) do
    {{:asc, quote(do: Ecto.Query.Builder.OrderBy.field!(unquote(kind), unquote(expr)))}, params_acc}
  end

  defp do_escape({dir, field}, params_acc, kind, _vars, _env) when is_atom(field) do
    {{quoted_dir!(kind, dir), Macro.escape(to_field(field))}, params_acc}
  end

  defp do_escape(field, params_acc, _kind, _vars, _env) when is_atom(field) do
    {{:asc, Macro.escape(to_field(field))}, params_acc}
  end

  defp do_escape({dir, expr}, params_acc, kind, vars, env) do
    {ast, params_acc} = Builder.escape(expr, :any, params_acc, vars, env)
    {{quoted_dir!(kind, dir), ast}, params_acc}
  end

  defp do_escape(expr, params_acc, _kind, vars, env) do
    {ast, params_acc} = Builder.escape(expr, :any, params_acc, vars, env)
    {{:asc, ast}, params_acc}
  end

  @doc """
  Checks the variable is a quoted direction at compilation time or
  delegate the check to runtime for interpolation.
  """
  def quoted_dir!(kind, {:^, _, [expr]}),
    do: quote(do: Ecto.Query.Builder.OrderBy.dir!(unquote(kind), unquote(expr)))
  def quoted_dir!(_kind, dir) when dir in @directions,
    do: dir
  def quoted_dir!(kind, other) do
    Builder.error!(
      "expected #{Enum.map_join(@directions, ", ", &inspect/1)} or interpolated value " <>
        "in `#{kind}`, got: `#{inspect other}`"
    )
  end

  @doc """
  Called by at runtime to verify the direction.
  """
  def dir!(_kind, dir) when dir in @directions,
    do: dir

  def dir!(kind, other) do
    raise ArgumentError,
      "expected one of #{Enum.map_join(@directions, ", ", &inspect/1)} " <>
        "in `#{kind}`, got: `#{inspect other}`"
  end

  @doc """
  Called at runtime to verify a field.
  """
  def field!(_kind, field) when is_atom(field) do
    to_field(field)
  end
  def field!(kind, other) do
    raise ArgumentError,
      "expected a field as an atom, a list or keyword list in `#{kind}`, got: `#{inspect other}`"
  end

  @doc """
  Called at runtime to verify order_by.
  """
  def order_by!(kind, exprs) do
    Enum.map List.wrap(exprs), fn
      {dir, field} when dir in @directions ->
        {dir, field!(kind, field)}
      field ->
        {:asc, field!(kind, field)}
    end
  end

  defp to_field(field), do: {{:., [], [{:&, [], [0]}, field]}, [], []}

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(query, binding, expr, env) do
    {query, binding} = Builder.escape_binding(query, binding, env)
    {expr, {params, _}} = escape(:order_by, expr, {[], :acc}, binding, env)
    params = Builder.escape_params(params)

    order_by = quote do: %Ecto.Query.QueryExpr{
                           expr: unquote(expr),
                           params: unquote(params),
                           file: unquote(env.file),
                           line: unquote(env.line)}
    Builder.apply_query(query, __MODULE__, [order_by], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.t
  def apply(%Ecto.Query{order_bys: order_bys} = query, expr) do
    %{query | order_bys: order_bys ++ [expr]}
  end
  def apply(query, expr) do
    apply(Ecto.Queryable.to_query(query), expr)
  end
end
