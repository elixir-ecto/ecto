import Kernel, except: [apply: 3]

defmodule Ecto.Query.Builder.LimitOffset do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Validates `with_ties` at runtime.
  """
  @spec with_ties!(any) :: boolean
  def with_ties!(with_ties) when is_boolean(with_ties), do: with_ties

  def with_ties!(with_ties),
    do: raise("`with_ties` expression must evaluate to a boolean at runtime, got: `#{inspect(with_ties)}`")

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(:limit | :with_ties | :offset, Macro.t(), [Macro.t()], Macro.t(), Macro.Env.t()) ::
          Macro.t()
  def build(type, query, binding, expr, env) do
    {query, vars} = Builder.escape_binding(query, binding, env)
    {expr, {params, _acc}} = escape(type, expr, {[], %{}}, vars, env)
    params = Builder.escape_params(params)
    quoted = build_quoted(type, expr, params, env)

    Builder.apply_query(query, __MODULE__, [type, quoted], env)
  end

  defp escape(type, expr, params_acc, vars, env) when type in [:limit, :offset] do
    Builder.escape(expr, :integer, params_acc, vars, env)
  end

  defp escape(:with_ties, expr, params_acc, _vars, _env) when is_boolean(expr) do
    {expr, params_acc}
  end

  defp escape(:with_ties, {:^, _, [expr]}, params_acc, _vars, _env) do
    {quote(do: Ecto.Query.Builder.LimitOffset.with_ties!(unquote(expr))), params_acc}
  end

  defp escape(:with_ties, expr, _params_acc, _vars, _env) do
    Builder.error!(
      "`with_ties` expression must be a compile time boolean or an interpolated value using ^, got: `#{Macro.to_string(expr)}`"
    )
  end

  defp build_quoted(:limit, expr, params, env) do
    quote do: %Ecto.Query.LimitExpr{
            expr: unquote(expr),
            params: unquote(params),
            file: unquote(env.file),
            line: unquote(env.line)
          }
  end

  defp build_quoted(:offset, expr, params, env) do
    quote do: %Ecto.Query.QueryExpr{
            expr: unquote(expr),
            params: unquote(params),
            file: unquote(env.file),
            line: unquote(env.line)
          }
  end

  defp build_quoted(:with_ties, expr, _params, _env), do: expr

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t(), :limit | :with_ties | :offset, term) :: Ecto.Query.t()
  def apply(%Ecto.Query{} = query, :limit, expr) do
    %{query | limit: expr}
  end

  def apply(%Ecto.Query{limit: limit} = query, :with_ties, expr) do
    %{query | limit: apply_limit(limit, expr)}
  end

  def apply(%Ecto.Query{} = query, :offset, expr) do
    %{query | offset: expr}
  end

  def apply(query, kind, expr) do
    apply(Ecto.Queryable.to_query(query), kind, expr)
  end

  @doc """
  Applies the `with_ties` value to the `limit` struct.
  """
  def apply_limit(nil, _with_ties) do
    Builder.error!("`with_ties` can only be applied to queries containing a `limit`")
  end

  # Runtime
  def apply_limit(%_{} = limit, with_ties) do
    %{limit | with_ties: with_ties}
  end

  # Compile
  def apply_limit(limit, with_ties) do
    quote do
      Ecto.Query.Builder.LimitOffset.apply_limit(unquote(limit), unquote(with_ties))
    end
  end
end
