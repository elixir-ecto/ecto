defmodule Ecto.Query.LockBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  @doc """
  Validates the expression is an integer or raise.
  """
  @spec validate(Macro.t) :: Macro.t | no_return
  def validate(expr) when is_boolean(expr), do: expr

  def validate(expr) do
    raise Ecto.QueryError, reason: "lock expression must be a boolean value" <>
                             ", got: #{inspect expr}"
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(:lock, Macro.t, Macro.t, Macro.Env.t) :: Macro.t
  def build(type, query, expr, env) do
    expr =
      case is_boolean(expr) do
        true  -> expr
        false -> quote do: unquote(__MODULE__).validate(unquote(expr))
      end
    BuilderUtil.apply_query(query, __MODULE__, [type, expr], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, :lock, term) :: Ecto.Query.Query.t
  def apply(query, :lock, value) do
    Ecto.Query.Query[] = query = Ecto.Queryable.to_query(query)
    query.lock(value)
  end

end
