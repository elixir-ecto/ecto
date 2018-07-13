import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Windows do
  @moduledoc false

  alias Ecto.Query.Builder
  alias Ecto.Query.Builder.OrderBy

  @doc """
  Escapes a window params.

  ## Examples

      iex> escape(quote do [x.x, [order_by: [desc: 13]]] end, {%{}, :acc}, [x: 0], __ENV__)
      {[
         fields: [
           {:{}, [],
            [{:{}, [], [:., [], [{:{}, [], [:&, [], [0]]}, :x]]}, [], []]}
         ],
         order_by: [desc: 13]
       ], {%{}, :acc}}

  """
  @spec escape([Macro.t], {map, term}, Keyword.t, Macro.Env.t | {Macro.Env.t, fun}) :: {Macro.t, {map, term}}
  def escape(args, params_acc, vars, env) do
    {fields_exp, opts} = escape_args(args)
    {fields, params_acc} = Builder.escape(fields_exp, :any, params_acc, vars, env)
    {opts, params_acc} = Enum.map_reduce(opts, params_acc, &escape_option(&1, &2, vars, env))
    {[{:fields, fields} | opts], params_acc}
  end

  defp escape_args([fields, opts]) when is_list(opts), do: {List.wrap(fields), opts}
  defp escape_args([fields]), do: {List.wrap(fields), []}

  defp escape_option({:order_by, expr}, params_acc, vars, env) do
    {expr, _} = OrderBy.escape(:order_by, expr, vars, env)
    {{:order_by, expr}, params_acc}
  end

  @spec escape_window(Macro.t, {map, term}, Keyword.t, Macro.Env.t | {Macro.Env.t, fun}) :: {Macro.t, {map, term}}
  def escape_window(expr, params_acc, vars, {env, _}) do
    escape_window(expr, params_acc, vars, env)
  end

  def escape_window(expr, params_acc, vars, env) do
    {expr, params_acc} = escape(expr, params_acc, vars, env)
    params = Builder.escape_params(elem(params_acc, 0))

    window = quote do: %Ecto.Query.QueryExpr{
                     expr: unquote(expr),
                     params: unquote(params),
                     file: unquote(env.file),
                     line: unquote(env.line)}
    {window, params_acc}
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

  defp build_window(vars, {name, {:partition_by, _, expr}}, env) do
    {window, _} = escape_window(expr, {%{}, :acc}, vars, env)
    {name, window}
  end

  @spec validate_windows!(Keyword.t, Keyword.t) :: Tuple.t
  def validate_windows!([], _), do: :ok
  def validate_windows!([{name, _} | rest], windows) do
    if Keyword.has_key?(windows, name) do
      Builder.error! "window with name #{name} is already defined"
    end

    validate_windows!(rest, windows)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, Keyword.t) :: Ecto.Query.t
  def apply(%Ecto.Query{windows: windows} = query, definitions) do
    validate_windows!(definitions, windows)
    %{query | windows: windows ++ definitions}
  end

  def apply(query, definitions) do
    apply(Ecto.Queryable.to_query(query), definitions)
  end
end
