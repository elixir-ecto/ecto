import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Windows do
  @moduledoc false

  alias Ecto.Query.Builder
  alias Ecto.Query.Builder.{GroupBy, OrderBy}
  @sort_order [:partition_by, :order_by, :frame]

  @doc """
  Escapes a window params.

  ## Examples

      iex> escape(quote do [order_by: [desc: 13]] end, {[], :acc}, [x: 0], __ENV__)
      {[order_by: [desc: 13]], [], {[], :acc}}

  """
  @spec escape([Macro.t], {list, term}, Keyword.t, Macro.Env.t | {Macro.Env.t, fun})
          :: {Macro.t, [{atom, term}], {list, term}}
  def escape(kw, params_acc, vars, env) when is_list(kw) do
    {compile, runtime} = sort(@sort_order, kw, :compile, [], [])
    {compile, params_acc} = Enum.map_reduce(compile, params_acc, &escape_compile(&1, &2, vars, env))
    {compile, runtime, params_acc}
  end

  def escape(kw, _params_acc, _vars, _env) do
    error!(kw)
  end

  defp sort([key | keys], kw, mode, compile, runtime) do
    case Keyword.pop(kw, key) do
      {nil, kw} ->
        sort(keys, kw, mode, compile, runtime)

      {{:^, _, [var]}, kw} ->
        sort(keys, kw, :runtime, compile, [{key, var} | runtime])

      {_, _} when mode == :runtime ->
        [{runtime_key, _} | _] = runtime
        raise ArgumentError, "window has an interpolated value under `#{runtime_key}` " <>
                             "and therefore `#{key}` must also be interpolated"

      {expr, kw} ->
        sort(keys, kw, mode, [{key, expr} | compile], runtime)
    end
  end

  defp sort([], [], _mode, compile, runtime) do
    {Enum.reverse(compile), Enum.reverse(runtime)}
  end

  defp sort([], kw, _mode, _compile, _runtime) do
    error!(kw)
  end

  defp escape_compile({:partition_by, fields}, params_acc, vars, env) do
    {fields, params_acc} = GroupBy.escape(:partition_by, fields, params_acc, vars, env)
    {{:partition_by, fields}, params_acc}
  end

  defp escape_compile({:order_by, fields}, params_acc, vars, env) do
    {fields, params_acc} = OrderBy.escape(:order_by, fields, params_acc, vars, env)
    {{:order_by, fields}, params_acc}
  end

  defp escape_compile({:frame, frame_clause}, params_acc, vars, env) do
    {frame_clause, params_acc} = escape_frame(frame_clause, params_acc, vars, env)
    {{:frame, frame_clause}, params_acc}
  end

  defp escape_frame({:fragment, _, _} = fragment, params_acc, vars, env) do
    Builder.escape(fragment, :any, params_acc, vars, env)
  end
  defp escape_frame(other, _, _, _) do
    Builder.error!("expected a dynamic or fragment in `:frame`, got: `#{inspect other}`")
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
    {:{}, [], [name, Enum.reverse(compile_acc), runtime_acc, Enum.reverse(params)]}
  end

  @doc """
  Invoked for runtime windows.
  """
  def runtime!(query, runtime, file, line) do
    windows =
      Enum.map(runtime, fn {name, compile_acc, runtime_acc, params} ->
        {acc, params} = do_runtime_window!(runtime_acc, query, compile_acc, params)
        expr = %Ecto.Query.QueryExpr{expr: Enum.reverse(acc), params: Enum.reverse(params), file: file, line: line}
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

  defp do_runtime_window!([{:frame, frame} | kw], query, acc, params) do
    case frame do
      %Ecto.Query.DynamicExpr{} ->
        {frame, params, _count} = Builder.Dynamic.partially_expand(:windows, query, frame, params, length(params))
        do_runtime_window!(kw, query, [{:frame, frame} | acc], params)

      _ ->
        raise ArgumentError,
                "expected a dynamic or fragment in `:frame`, got: `#{inspect frame}`"
    end
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
