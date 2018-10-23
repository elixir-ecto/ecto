import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Combination do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(atom, Macro.t, Macro.t, Macro.Env.t) :: Macro.t
  def build(kind, query, {:^, _, [expr]}, env) do
    expr = quote do: Ecto.Queryable.to_query(unquote(expr))
    Builder.apply_query(query, __MODULE__, [[{kind, expr}]], env)
  end

  def build(kind, _query, other, _env) do
    Builder.error! "`#{Macro.to_string(other)}` is not a valid #{kind}. " <>
                   "#{kind} must always be an interpolated query, such as ^existing_query"
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.t
  def apply(%Ecto.Query{combinations: combinations} = query, value) do
    %{query | combinations: combinations ++ value}
  end
  def apply(query, value) do
    apply(Ecto.Queryable.to_query(query), value)
  end
end
