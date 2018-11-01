import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Windows do
  @moduledoc false

  alias Ecto.Query.Builder
  alias Ecto.Query.Builder.{GroupBy, OrderBy}

  @doc """
  Escapes a window params.

  ## Examples

      iex> escape(quote do [order_by: [desc: 13]] end, {[], :acc}, [x: 0], __ENV__)
      {[order_by: [desc: 13]], {[], :acc}}

  """
  @spec escape([Macro.t], {list, term}, Keyword.t, Macro.Env.t | {Macro.Env.t, fun}) :: {Macro.t, {list, term}}
  def escape(kw, params_acc, vars, env) when is_list(kw) do
    Enum.map_reduce(kw, params_acc, &do_escape(&1, &2, vars, env))
  end

  def escape(kw, _params_acc, _vars, _env) do
    error!(kw)
  end

  defp do_escape({:partition_by, fields}, params_acc, vars, env) do
    {fields, params_acc} = GroupBy.escape(:partition_by, fields, params_acc, vars, env)
    {{:partition_by, fields}, params_acc}
  end

  defp do_escape({:order_by, fields}, params_acc, vars, env) do
    {fields, params_acc} = OrderBy.escape(:order_by, fields, params_acc, vars, env)
    {{:order_by, fields}, params_acc}
  end

  defp do_escape({:frame, frame_clause}, params_acc, vars, env) do
    {frame_clause, params_acc} = escape_frame(frame_clause, params_acc, vars, env)
    {{:frame, frame_clause}, params_acc}
  end

  defp do_escape(other, _params_acc, _vars, _env) do
    error!(other)
  end

  defp escape_frame({:fragment, _, _} = fragment, params_acc, vars, env) do
    Builder.escape(fragment, :any, params_acc, vars, env)
  end
  defp escape_frame(other, _, _, _) do
    Builder.error!("expected a fragment in `:frame`, got: `#{inspect other}`")
  end

  defp error!(other) do
    Builder.error!(
      "expected window definition to be a keyword list " <>
        "with partition_by, order_by or frame as keys, got: `#{inspect other}`"
    )
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Keyword.t, Macro.Env.t) :: Macro.t
  def build(query, binding, windows, env) when is_list(windows) do
    {query, binding} = Builder.escape_binding(query, binding, env)
    windows = Enum.map(windows, &build_window(binding, &1, env))
    Builder.apply_query(query, __MODULE__, [windows], env)
  end

  def build(_, _, windows, _) do
    Builder.error!(
      "expected window definitions to be a keyword list with window names as keys and " <>
        "a keyword list with the window definition as value, got: `#{inspect windows}`"
    )
  end

  defp build_window(vars, {name, expr}, env) do
    {expr, {params, _}} = escape(expr, {[], :acc}, vars, env)
    params = Builder.escape_params(params)

    window = quote do
      %Ecto.Query.QueryExpr{
        expr: unquote(expr),
        params: unquote(params),
        file: unquote(env.file),
        line: unquote(env.line)
      }
    end

    {name, window}
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, Keyword.t) :: Ecto.Query.t
  def apply(%Ecto.Query{windows: windows} = query, definitions) do
    merged = Keyword.merge(windows, definitions, fn name, _, _ ->
      Builder.error! "window with name #{name} is already defined"
    end)

    %{query | windows: merged}
  end

  def apply(query, definitions) do
    apply(Ecto.Queryable.to_query(query), definitions)
  end
end
