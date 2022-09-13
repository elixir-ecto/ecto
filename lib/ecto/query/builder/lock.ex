import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Lock do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Escapes the lock code.

      iex> escape(quote(do: "FOO"), [], __ENV__)
      "FOO"

  """
  @spec escape(Macro.t(), Keyword.t, Macro.Env.t) :: Macro.t()
  def escape(lock, _vars, _env) when is_binary(lock), do: lock

  def escape({:fragment, _, [_ | _]} = expr, vars, env) do
    {expr, {params, _acc}} = Builder.escape(expr, :any, {[], %{}}, vars, env)

    if params != [] do
      Builder.error!("value interpolation is not allowed in :lock")
    end

    expr
  end

  def escape(other, _, _) do
    Builder.error!(
      "`#{Macro.to_string(other)}` is not a valid lock. " <>
        "For security reasons, a lock must always be a literal string or a fragment"
    )
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t(), Macro.t(), Macro.t(), Macro.Env.t()) :: Macro.t()
  def build(query, binding, expr, env) do
    {query, binding} = Builder.escape_binding(query, binding, env)
    Builder.apply_query(query, __MODULE__, [escape(expr, binding, env)], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t(), term) :: Ecto.Query.t()
  def apply(%Ecto.Query{} = query, value) do
    %{query | lock: value}
  end

  def apply(query, value) do
    apply(Ecto.Queryable.to_query(query), value)
  end
end
