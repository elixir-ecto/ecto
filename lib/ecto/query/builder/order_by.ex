defmodule Ecto.Query.Builder.OrderBy do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes an order by query.

  The query is escaped to a list of `{direction, expression}`
  pairs at runtime. Escaping also validates direction is one of
  `:asc` or `:desc`.

  ## Examples

      iex> escape(quote do [x.x, desc: 13] end, [x: 0], __ENV__)
      {[asc: {:{}, [], [{:{}, [], [:., [], [{:{}, [], [:&, [], [0]]}, :x]]}, [], []]},
        desc: 13],
       %{}}

  """
  @spec escape(Macro.t, Keyword.t, Macro.Env.t) :: Macro.t
  def escape({:^, _, [expr]}, _vars, _env) do
    {quote(do: Ecto.Query.Builder.OrderBy.order_by!(unquote(expr))), %{}}
  end

  def escape(expr, vars, env) do
    List.wrap(expr)
    |> Enum.map_reduce(%{}, &do_escape(&1, &2, vars, env))
  end

  defp do_escape({dir, {:^, _, [expr]}}, params, _vars, _env) do
    {{quoted_dir!(dir), quote(do: Ecto.Query.Builder.OrderBy.field!(unquote(expr)))}, params}
  end

  defp do_escape({:^, _, [expr]}, params, _vars, _env) do
    {{:asc, quote(do: Ecto.Query.Builder.OrderBy.field!(unquote(expr)))}, params}
  end

  defp do_escape({dir, field}, params, _vars, _env) when is_atom(field) do
    {{quoted_dir!(dir), Macro.escape(to_field(field))}, params}
  end

  defp do_escape(field, params, _vars, _env) when is_atom(field) do
    {{:asc, Macro.escape(to_field(field))}, params}
  end

  defp do_escape({dir, expr}, params, vars, env) do
    {ast, params} = Builder.escape(expr, :any, params, vars, env)
    {{quoted_dir!(dir), ast}, params}
  end

  defp do_escape(expr, params, vars, env) do
    {ast, params} = Builder.escape(expr, :any, params, vars, env)
    {{:asc, ast}, params}
  end

  @doc """
  Checks the variable is a quoted direction at compilation time or
  delegate the check to runtime for interpolation.
  """
  def quoted_dir!({:^, _, [expr]}),
    do: quote(do: Ecto.Query.Builder.OrderBy.dir!(unquote(expr)))
  def quoted_dir!(dir) when dir in [:asc, :desc],
    do: dir
  def quoted_dir!(other),
    do: Builder.error!("expected :asc, :desc or interpolated value in `order_by`, got: `#{inspect other}`")

  @doc """
  Called by at runtime to verify the direction.
  """
  def dir!(dir) when dir in [:asc, :desc],
    do: dir
  def dir!(other),
    do: Builder.error!("expected :asc or :desc in `order_by`, got: `#{inspect other}`")

  @doc """
  Called at runtime to verify a field.
  """
  def field!(field) when is_atom(field),
    do: to_field(field)
  def field!(other),
    do: Builder.error!("expected a field as an atom in `order_by`, got: `#{inspect other}`")

  @doc """
  Called at runtime to verify order_by.
  """
  def order_by!(order_by) do
    Enum.map List.wrap(order_by), fn
      {dir, field} when dir in [:asc, :desc] and is_atom(field) ->
        {dir, to_field(field)}
      field when is_atom(field) ->
        {:asc, to_field(field)}
      _ ->
        Builder.error!("expected a list or keyword list of fields in `order_by`, got: `#{inspect order_by}`")
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
    binding        = Builder.escape_binding(binding)
    {expr, params} = escape(expr, binding, env)
    params         = Builder.escape_params(params)

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
  def apply(query, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | order_bys: query.order_bys ++ [expr]}
  end
end
