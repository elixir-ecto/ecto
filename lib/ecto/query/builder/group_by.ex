import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.GroupBy do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes a list of quoted expressions.

  See `Ecto.Builder.escape/2`.

      iex> escape(quote do [x.x, 13] end, [x: 0], __ENV__)
      {[{:{}, [], [{:{}, [], [:., [], [{:{}, [], [:&, [], [0]]}, :x]]}, [], []]},
        13],
       %{}}
  """
  @spec escape(Macro.t, Keyword.t, Macro.Env.t) :: Macro.t
  def escape({:^, _, [expr]}, _vars, _env) do
    {quote(do: Ecto.Query.Builder.GroupBy.group_by!(unquote(expr))), %{}}
  end

  def escape(expr, vars, env) do
    expr
    |> List.wrap
    |> Enum.map_reduce(%{}, &do_escape(&1, &2, vars, env))
  end

  defp do_escape({:^, _, [expr]}, params, _vars, _env) do
    {quote(do: Ecto.Query.Builder.GroupBy.field!(unquote(expr))), params}
  end

  defp do_escape(field, params, _vars, _env) when is_atom(field) do
    {Macro.escape(to_field(field)), params}
  end

  defp do_escape(expr, params, vars, env) do
    {expr, {params, :acc}} = Builder.escape(expr, :any, {params, :acc}, vars, env)
    {expr, params}
  end

  @doc """
  Called at runtime to verify a field.
  """
  def field!(field) when is_atom(field),
    do: to_field(field)
  def field!(other) do
    raise ArgumentError,
      "expected a field as an atom in `group_by`, got: `#{inspect other}`"
  end

  @doc """
  Called at runtime to verify group_by.
  """
  def group_by!(group_by) do
    Enum.map List.wrap(group_by), fn
      field when is_atom(field) ->
        to_field(field)
      _ ->
        raise ArgumentError,
          "expected a list of fields in `group_by`, got: `#{inspect group_by}`"
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
    {query, binding} = Builder.escape_binding(query, binding)
    {expr, params} = escape(expr, binding, env)
    params = Builder.escape_params(params)

    group_by = quote do: %Ecto.Query.QueryExpr{
                           expr: unquote(expr),
                           params: unquote(params),
                           file: unquote(env.file),
                           line: unquote(env.line)}
    Builder.apply_query(query, __MODULE__, [group_by], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.t
  def apply(%Ecto.Query{group_bys: group_bys} = query, expr) do
    %{query | group_bys: group_bys ++ [expr]}
  end
  def apply(query, expr) do
    apply(Ecto.Queryable.to_query(query), expr)
  end
end
