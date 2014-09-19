defmodule Ecto.Query.Builder.LimitOffset do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Validates the expression is an integer or raise.
  """
  @spec validate(Macro.t) :: Macro.t | no_return
  def validate(expr) when is_integer(expr), do: expr

  def validate(expr) do
    raise Ecto.QueryError, reason: "limit and offset expressions must be a single " <>
                                   "integer value, got: #{inspect expr}"
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(:limit | :offset, Macro.t, Macro.t, Macro.Env.t) :: Macro.t
  def build(type, query, expr, env) do
    {expr, external} = Builder.escape(expr, [])
    external = Builder.escape_external(external)

    limoff = quote do: %Ecto.Query.QueryExpr{
                        expr: unquote(expr),
                        external: unquote(external),
                        file: unquote(env.file),
                        line: unquote(env.line)}

    Builder.apply_query(query, __MODULE__, [type, limoff], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, :limit | :offset, term) :: Ecto.Query.t
  def apply(query, :limit, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | limit: expr}
  end

  def apply(query, :offset, expr) do
    query = Ecto.Queryable.to_query(query)
    %{query | offset: expr}
  end
end
