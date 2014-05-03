defmodule Ecto.Query.LimitOffsetBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

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
    expr =
      case is_integer(expr) do
        true  -> expr
        false -> quote do: unquote(__MODULE__).validate(unquote(expr))
      end
    BuilderUtil.apply_query(query, __MODULE__, [type, expr], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, :limit | :offset, term) :: Ecto.Query.t
  def apply(query, :limit, value) do
    query = Ecto.Queryable.to_query(query)
    %{query | limit: value}
  end

  def apply(query, :offset, value) do
    query = Ecto.Queryable.to_query(query)
    %{query | offset: value}
  end
end
