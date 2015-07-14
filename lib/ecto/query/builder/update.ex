defmodule Ecto.Query.Builder.Update do
  @moduledoc false

  @keys [:set, :inc, :push, :pull]
  alias Ecto.Query.Builder

  @doc """
  Escapes a list of quoted expressions.

      iex> escape([], [], __ENV__)
      {[], [], %{}}

      iex> escape([set: []], [], __ENV__)
      {[set: []], [], %{}}

      iex> escape(quote(do: ^[set: []]), [], __ENV__)
      {[], [set: []], %{}}

      iex> escape(quote(do: [set: ^[foo: 1]]), [], __ENV__)
      {[], [set: [foo: 1]], %{}}

      iex> escape(quote(do: [set: [foo: ^1]]), [], __ENV__)
      {[set: [foo: {:{}, [], [:^, [], [0]]}]], [], %{0 => {1, {0, :foo}}}}

  """
  @spec escape(Macro.t, Keyword.t, Macro.Env.t) :: {Macro.t, Macro.t, %{}}
  def escape(expr, vars, env) when is_list(expr) do
    escape_op(expr, [], [], %{}, vars, env)
  end

  def escape({:^, _, [v]}, _vars, _env) do
    {[], v, %{}}
  end

  def escape(expr, _vars, _env) do
    compile_error!(expr)
  end

  defp escape_op([{k, v}|t], compile, runtime, params, vars, env) when is_atom(k) and is_list(v) do
    validate_key!(k)
    {v, params} = escape_field(k, v, params, vars, env)
    escape_op(t, [{k, v}|compile], runtime, params, vars, env)
  end

  defp escape_op([{k, {:^, _, [v]}}|t], compile, runtime, params, vars, env) when is_atom(k) do
    validate_key!(k)
    escape_op(t, compile, [{k, v}|runtime], params, vars, env)
  end

  defp escape_op([], compile, runtime, params, _vars, _env) do
    {Enum.reverse(compile), Enum.reverse(runtime), params}
  end

  defp escape_op(expr, _compile, _runtime, _params, _vars, _env) do
    compile_error!(expr)
  end

  defp escape_field(key, kw, params, vars, env) do
    Enum.map_reduce kw, params, fn
      {k, v}, acc when is_atom(k) ->
        {v, params} = Builder.escape(v, type_for_key(key, {0, k}), acc, vars, env)
        {{k, v}, params}
      _, _acc ->
        Builder.error! "malformed #{inspect key} in update `#{Macro.to_string(kw)}`, " <>
                       "expected a keyword list"
    end
  end

  defp compile_error!(expr) do
    Builder.error! "malformed update `#{Macro.to_string(expr)}` in query expression, " <>
                   "expected a keyword list with lists or interpolated expressions as values"
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(query, binding, expr, env) do
    binding = Builder.escape_binding(binding)
    {compile, runtime, params} = escape(expr, binding, env)

    query =
      if compile == [] do
        query
      else
        params = Builder.escape_params(params)

        update = quote do
          %Ecto.Query.QueryExpr{expr: unquote(compile), params: unquote(params),
                                file: unquote(env.file), line: unquote(env.line)}
        end

        Builder.apply_query(query, __MODULE__, [update], env)
      end

    query =
      if runtime == [] do
        query
      else
        update = quote do
          Ecto.Query.Builder.Update.runtime(unquote(runtime), unquote(env.line), unquote(env.file))
        end

        Builder.apply_query(query, __MODULE__, [update], env)
      end

    query
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.t
  def apply(query, updates) do
    query = Ecto.Queryable.to_query(query)
    %{query | updates: query.updates ++ [updates]}
  end

  @doc """
  If there are interpolated updates at compile time,
  we need to handle them at runtime. We do such in
  this callback.
  """
  @spec runtime(term, line :: integer, file :: binary) :: Ecto.Query.t
  def runtime(runtime, line, file) when is_list(runtime) do
    {runtime, {params, _count}} =
      Enum.map_reduce runtime, {[], 0}, fn
        {k, v}, acc when is_atom(k) and is_list(v) ->
          validate_key!(k)
          {v, params} = runtime_field(k, v, acc)
          {{k, v}, params}
        _, _acc ->
          runtime_error! runtime
      end

    %Ecto.Query.QueryExpr{expr: runtime, params: Enum.reverse(params),
                          file: file, line: line}
  end

  def runtime(runtime, _line, _file) do
    runtime_error!(runtime)
  end

  defp runtime_field(key, kw, acc) do
    Enum.map_reduce kw, acc, fn
      {k, v}, {params, count} when is_atom(k) ->
        params = [{v, type_for_key(key, {0, k})}|params]
        {{k, {:^, [], [count]}}, {params, count+1}}
      _, _acc ->
        Builder.error! "malformed #{inspect key} in update `#{inspect(kw)}`, " <>
                       "expected a keyword list"
    end
  end

  defp runtime_error!(value) do
    Builder.error! "malformed update `#{inspect(value)}` in query expression, " <>
                   "expected a keyword list with lists or interpolated expressions as values"
  end

  defp validate_key!(key) when key in @keys, do: :ok
  defp validate_key!(key) do
    Builder.error! "unknown key `#{inspect(key)}` in update"
  end

  defp type_for_key(:push, type), do: {:in_array, type}
  defp type_for_key(:pull, type), do: {:in_array, type}
  defp type_for_key(_, type),     do: type
end
