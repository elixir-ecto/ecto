import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Lock do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes the lock code.

      iex> escape(quote do: "FOO")
      "FOO"

  """
  @spec escape(Macro.t) :: Macro.t | no_return
  def escape(lock) when is_binary(lock), do: lock

  def escape(other) do
    Builder.error! "`#{Macro.to_string(other)}` is not a valid lock. " <>
                   "For security reasons, a lock must always be a literal string"
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, Macro.t, Macro.Env.t) :: Macro.t
  def build(query, expr, env) do
    Builder.apply_query(query, __MODULE__, [escape(expr)], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t, term) :: Ecto.Query.t
  def apply(%Ecto.Query{} = query, value) do
    %{query | lock: value}
  end
  def apply(query, value) do
    apply(Ecto.Queryable.to_query(query), value)
  end
end
