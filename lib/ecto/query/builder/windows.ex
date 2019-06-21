import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Windows do
  @moduledoc false

  alias Ecto.Query.Builder
  alias Ecto.Query.Builder.{GroupBy, OrderBy}

  @doc """
  Escapes a window params.

  ## Examples

      iex> escape(quote do [order_by: [desc: 13]] end, {[], :acc}, [x: 0], __ENV__)
      {[order_by: [desc: 13]], [], {[], :acc}}

  """
  @spec escape([Macro.t], {list, term}, Keyword.t, Macro.Env.t | {Macro.Env.t, fun}) :: {Macro.t, {list, term}}
  def escape(kw, params_acc, vars, env) when is_list(kw) do
    escape(kw, params_acc, vars, env, [], [])
  end

  def escape(kw, _params_acc, _vars, _env) do
    error!(kw)
  end

  defp escape([{key, {:^, _, [var]}} | kw], params_acc, vars, env, compile_acc, runtime_acc)
       when key in [:partition_by, :order_by] do
    escape(kw, params_acc, vars, env, compile_acc, [{key, var} | runtime_acc])
  end

  defp escape([{:partition_by, fields} | kw], params_acc, vars, env, compile_acc, runtime_acc) do
    {fields, params_acc} = GroupBy.escape(:partition_by, fields, params_acc, vars, env)
    escape(kw, params_acc, vars, env, [{:partition_by, fields} | compile_acc], runtime_acc)
  end

  defp escape([{:order_by, fields} | kw], params_acc, vars, env, compile_acc, runtime_acc) do
    {fields, params_acc} = OrderBy.escape(:order_by, fields, params_acc, vars, env)
    escape(kw, params_acc, vars, env, [{:order_by, fields} | compile_acc], runtime_acc)
  end

  defp escape([{:frame, frame_clause} | kw], params_acc, vars, env, compile_acc, runtime_acc) do
    {frame_clause, params_acc} = escape_frame(frame_clause, params_acc, vars, env)
    escape(kw, params_acc, vars, env, [{:frame, frame_clause} | compile_acc], runtime_acc)
  end

  defp escape([other | _], _params_acc, _vars, _env, _compile_acc, _runtime_acc) do
    error!(other)
  end

  defp escape([], params_acc, _vars, _env, compile_acc, runtime_acc) do
    {compile_acc, runtime_acc, params_acc}
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

    {compile, runtime} =
      windows
      |> Enum.map(&escape_window(binding, &1, env))
      |> Enum.split_with(&elem(&1, 2) == [])

    compile = Enum.map(compile, &build_compile_window(&1, env))
    runtime = Enum.map(runtime, &build_runtime_window(&1, env))
    query = Builder.apply_query(query, __MODULE__, [compile], env)

    if runtime == [] do
      query
    else
      quote do
        Ecto.Query.Builder.Windows.runtime!(
          unquote(query),
          unquote(runtime),
          unquote(env.file),
          unquote(env.line)
        )
      end
    end
  end

  def build(_, _, windows, _) do
    Builder.error!(
      "expected window definitions to be a keyword list with window names as keys and " <>
        "a keyword list with the window definition as value, got: `#{inspect windows}`"
    )
  end

  defp escape_window(vars, {name, expr}, env) do
    {compile_acc, runtime_acc, {params, _}} = escape(expr, {[], :acc}, vars, env)
    {name, compile_acc, runtime_acc, Builder.escape_params(params)}
  end

  defp build_compile_window({name, compile_acc, _, params}, env) do
    {name,
     quote do
       %Ecto.Query.QueryExpr{
         expr: unquote(compile_acc),
         params: unquote(params),
         file: unquote(env.file),
         line: unquote(env.line)
       }
     end}
  end

  defp build_runtime_window({name, compile_acc, runtime_acc, params}, _env) do
    {:{}, [], [name, compile_acc, runtime_acc, Enum.reverse(params)]}
  end

  @doc """
  Invoked for runtime windows.
  """
  def runtime!(query, runtime, file, line) do
    windows =
      Enum.map(runtime, fn {name, compile_acc, runtime_acc, params} ->
        {acc, params} = do_runtime_window!(runtime_acc, query, compile_acc, params)
        expr = %Ecto.Query.QueryExpr{expr: acc, params: Enum.reverse(params), file: file, line: line}
        {name, expr}
      end)

    apply(query, windows)
  end

  defp do_runtime_window!([{:order_by, order_by} | kw], query, acc, params) do
    {order_by, params} = OrderBy.order_by_or_distinct!(:order_by, query, order_by, params)
    do_runtime_window!(kw, query, [{:order_by, order_by} | acc], params)
  end

    defp do_runtime_window!([{:partition_by, partition_by} | kw], query, acc, params) do
    {partition_by, params} = GroupBy.group_or_partition_by!(:partition_by, query, partition_by, params)
    do_runtime_window!(kw, query, [{:partition_by, partition_by} | acc], params)
  end

  defp do_runtime_window!([], _query, acc, params), do: {acc, params}

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
