import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Update do
  @moduledoc false

  @keys [:set, :inc, :push, :pull]
  alias Ecto.Query.Builder

  @doc """
  Escapes a list of quoted expressions.

      iex> escape([], [], __ENV__)
      {[], [], []}

      iex> escape([set: []], [], __ENV__)
      {[], [], []}

      iex> escape(quote(do: ^[set: []]), [], __ENV__)
      {[], [set: []], []}

      iex> escape(quote(do: [set: ^[foo: 1]]), [], __ENV__)
      {[], [set: [foo: 1]], []}

      iex> escape(quote(do: [set: [foo: ^1]]), [], __ENV__)
      {[], [set: [foo: 1]], []}

  """
  @spec escape(Macro.t, Keyword.t, Macro.Env.t) :: {Macro.t, Macro.t, list}
  def escape(expr, vars, env) when is_list(expr) do
    escape_op(expr, [], [], [], vars, env)
  end

  def escape({:^, _, [v]}, _vars, _env) do
    {[], v, []}
  end

  def escape(expr, _vars, _env) do
    compile_error!(expr)
  end

  defp escape_op([{k, v}|t], compile, runtime, params, vars, env) when is_atom(k) and is_list(v) do
    validate_op!(k)
    {compile_values, runtime_values, params} = escape_kw(k, v, params, vars, env)
    compile =
      if compile_values == [], do: compile, else: [{k, Enum.reverse(compile_values)} | compile]
    runtime =
      if runtime_values == [], do: runtime, else: [{k, Enum.reverse(runtime_values)} | runtime]
    escape_op(t, compile, runtime, params, vars, env)
  end

  defp escape_op([{k, {:^, _, [v]}}|t], compile, runtime, params, vars, env) when is_atom(k) do
    validate_op!(k)
    escape_op(t, compile, [{k, v}|runtime], params, vars, env)
  end

  defp escape_op([], compile, runtime, params, _vars, _env) do
    {Enum.reverse(compile), Enum.reverse(runtime), params}
  end

  defp escape_op(expr, _compile, _runtime, _params, _vars, _env) do
    compile_error!(expr)
  end

  defp escape_kw(op, kw, params, vars, env) do
    Enum.reduce kw, {[], [], params}, fn
      {k, {:^, _, [v]}}, {compile, runtime, params} when is_atom(k) ->
        {compile, [{k, v} | runtime], params}
      {k, v}, {compile, runtime, params} ->
        k = escape_field!(k)
        {v, {params, :acc}} = Builder.escape(v, type_for_key(op, {0, k}), {params, :acc}, vars, env)
        {[{k, v} | compile], runtime, params}
      _, _acc ->
        Builder.error! "malformed #{inspect op} in update `#{Macro.to_string(kw)}`, " <>
                       "expected a keyword list"
    end
  end

  defp escape_field!({:^, _, [k]}), do: quote(do: Ecto.Query.Builder.Update.field!(unquote(k)))
  defp escape_field!(k) when is_atom(k), do: k

  defp escape_field!(k) do
    Builder.error!(
      "expected an atom field or an interpolated field in `update`, got `#{inspect(k)}`"
    )
  end

  def field!(field) when is_atom(field), do: field

  def field!(other) do
    raise ArgumentError, "expected a field as an atom in `update`, got: `#{inspect other}`"
  end

  defp compile_error!(expr) do
    Builder.error! "malformed update `#{Macro.to_string(expr)}` in query expression, " <>
                   "expected a keyword list with set/push/pop as keys with field-value " <>
                   "pairs as values"
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, [Macro.t], Macro.t, Macro.Env.t) :: Macro.t
  def build(query, binding, expr, env) do
    {query, binding} = Builder.escape_binding(query, binding, env)
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

    if runtime == [] do
      query
    else
      quote do
        Ecto.Query.Builder.Update.update!(unquote(query), unquote(runtime),
                                          unquote(env.file), unquote(env.line))
      end
    end
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.t
  def apply(%Ecto.Query{updates: updates} = query, expr) do
    %{query | updates: updates ++ [expr]}
  end
  def apply(query, expr) do
    apply(Ecto.Queryable.to_query(query), expr)
  end

  @doc """
  If there are interpolated updates at compile time,
  we need to handle them at runtime. We do such in
  this callback.
  """
  def update!(query, runtime, file, line) when is_list(runtime) do
    {runtime, {params, _count}} =
      Enum.map_reduce runtime, {[], 0}, fn
        {k, v}, acc when is_atom(k) and is_list(v) ->
          validate_op!(k)
          {v, params} = runtime_field!(query, k, v, acc)
          {{k, v}, params}
        _, _ ->
          runtime_error!(runtime)
      end

    expr = %Ecto.Query.QueryExpr{expr: runtime, params: Enum.reverse(params),
                                 file: file, line: line}

    apply(query, expr)
  end

  def update!(_query, runtime, _file, _line) do
    runtime_error!(runtime)
  end

  defp runtime_field!(query, key, kw, acc) do
    Enum.map_reduce kw, acc, fn
      {k, %Ecto.Query.DynamicExpr{} = v}, {params, count} when is_atom(k) ->
        {v, params, count} = Ecto.Query.Builder.Dynamic.partially_expand(query, v, params, count)
        {{k, v}, {params, count}}
      {k, v}, {params, count} when is_atom(k) ->
        params = [{v, type_for_key(key, {0, k})} | params]
        {{k, {:^, [], [count]}}, {params, count + 1}}
      _, _acc ->
        raise ArgumentError, "malformed #{inspect key} in update `#{inspect(kw)}`, " <>
                             "expected a keyword list"
    end
  end

  defp runtime_error!(value) do
    raise ArgumentError,
          "malformed update `#{inspect(value)}` in query expression, " <>
          "expected a keyword list with set/push/pop as keys with field-value pairs as values"
  end

  defp validate_op!(key) when key in @keys, do: :ok
  defp validate_op!(key), do: Builder.error! "unknown key `#{inspect(key)}` in update"

  # Out means the given type must be taken out of an array
  # It is the opposite of "left in right" in the query API.
  defp type_for_key(:push, type), do: {:out, type}
  defp type_for_key(:pull, type), do: {:out, type}
  defp type_for_key(_, type),     do: type
end
