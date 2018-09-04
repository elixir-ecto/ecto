import Kernel, except: [apply: 3]

defmodule Ecto.Query.Builder.Union do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(:union | :union_all, Macro.t, Macto.t, Macro.Env.t) :: Macro.t
  def build(type, query, other_query, env) do
    Builder.apply_query(query, __MODULE__, [type, other_query], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, :union | :union_all, Macro.t) :: Ecto.Query.t
  def apply(%Ecto.Query{unions: unions} = query, type, other_query) do
    %{query | unions: unions ++ [{type, other_query}]}
  end
  def apply(query, type, other_query) do
    apply(Ecto.Queryable.to_query(query), type, other_query)
  end
end
