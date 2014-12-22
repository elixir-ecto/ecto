defmodule Ecto.Query.Builder.Lock do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes the lock code.

      iex> escape(quote do: true)
      true

      iex> escape(quote do: "FOO")
      "FOO"

  """
  @spec escape(Macro.t) :: Macro.t | no_return
  def escape(lock) when is_boolean(lock) or is_binary(lock), do: lock

  def escape({:^, _, [lock]}) do
    quote do: unquote(__MODULE__).lock!(unquote(lock))
  end

  def escape(other) do
    Builder.error! "`#{Macro.to_string(other)}` is not a valid lock expression, " <>
                   "use ^ if you want to interpolate a value"
  end

  @doc """
  Validates the expression is an integer or raise.
  """
  def lock!(lock) when is_boolean(lock) or is_binary(lock), do: lock

  def lock!(lock) do
    Builder.error! "invalid lock `#{inspect lock}`. lock must be a boolean value " <>
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
    Builder.apply_query(query, __MODULE__, [escape(expr)], env)
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
