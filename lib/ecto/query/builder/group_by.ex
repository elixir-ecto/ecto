import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.GroupBy do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes a list of quoted expressions.

  See `Ecto.Builder.escape/2`.

      iex> escape(:group_by, quote do [x.x, 13] end, {[], :acc}, [x: 0], __ENV__)
      {[{:{}, [], [{:{}, [], [:., [], [{:{}, [], [:&, [], [0]]}, :x]]}, [], []]},
        13],
       {[], :acc}}
  """
  @spec escape(:group_by | :partition_by, Macro.t, {list, term}, Keyword.t, Macro.Env.t) ::
          {Macro.t, {list, term}}
  def escape(kind, expr, params_acc, vars, env) do
    expr
    |> List.wrap
    |> Enum.map_reduce(params_acc, &do_escape(&1, &2, kind, vars, env))
  end

  defp do_escape({:^, _, [expr]}, params_acc, kind, _vars, _env) do
    {quote(do: Ecto.Query.Builder.GroupBy.field!(unquote(kind), unquote(expr))), params_acc}
  end

  defp do_escape(field, params_acc, _kind, _vars, _env) when is_atom(field) do
    {Macro.escape(to_field(field)), params_acc}
  end

  defp do_escape(expr, params_acc, _kind, vars, env) do
    Builder.escape(expr, :any, params_acc, vars, env)
  end

  @doc """
  Called at runtime to verify a field.
  """
  def field!(_kind, field) when is_atom(field),
    do: to_field(field)
  def field!(kind, other) do
    raise ArgumentError,
      "expected a field as an atom in `#{kind}`, got: `#{inspect other}`"
  end

  @doc """
  Shared between group_by and partition_by.
  """
  def group_or_partition_by!(kind, query, exprs, params) do
    {expr, {params, _}} =
      Enum.map_reduce(List.wrap(exprs), {params, length(params)}, fn
        field, params_count when is_atom(field) ->
          {to_field(field), params_count}

        %Ecto.Query.DynamicExpr{} = dynamic, {params, count} ->
          {expr, params, count} = Builder.Dynamic.partially_expand(kind, query, dynamic, params, count)
          {expr, {params, count}}

        other, _params_count ->
          raise ArgumentError,
                "expected a list of fields and dynamics in `#{kind}`, got: `#{inspect other}`"
      end)

    {expr, params}
  end

  defp to_field(field), do: {{:., [], [{:&, [], [0]}, field]}, [], []}

  @doc """
  Called at runtime to assemble group_by.
  """
  def group_by!(query, group_by, file, line) do
    {expr, params} = group_or_partition_by!(:group_by, query, group_by, [])
    expr = %Ecto.Query.QueryExpr{expr: expr, params: Enum.reverse(params), line: line, file: file}
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
      Ecto.Query.Builder.GroupBy.group_by!(unquote(query), unquote(var), unquote(env.file), unquote(env.line))
    end
  end

  def build(query, binding, expr, env) do
    {query, binding} = Builder.escape_binding(query, binding, env)
    {expr, {params, _}} = escape(:group_by, expr, {[], :acc}, binding, env)
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
