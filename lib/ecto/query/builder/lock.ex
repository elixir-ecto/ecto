defmodule Ecto.Query.Builder.Lock do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Validates the expression is an integer or raise.
  """
  @spec lock!(Macro.t) :: Macro.t | no_return
  def lock!(expr) when is_boolean(expr) or is_binary(expr), do: expr

  def lock!(expr) do
    Builder.error! "invalid lock `#{inspect expr}`. lock must be a boolean value " <>
                   "or a string containing the database-specific locking clause"
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, Macro.t, Macro.Env.t) :: Macro.t
  def build(query, expr, env) do
    expr =
      case is_boolean(expr) or is_binary(expr) do
        true  -> expr
        false -> quote do: unquote(__MODULE__).lock!(unquote(expr))
      end
    Builder.apply_query(query, __MODULE__, [expr], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.t
  def apply(query, value) do
    query = Ecto.Queryable.to_query(query)
    %{query | lock: value}
  end
end
