defmodule Ecto.Query.Builder.From do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Handles from expressions.

  The expressions may either contain an `in` expression or not.
  The right side is always expected to Queryable.

  ## Examples

      iex> escape(quote do: MyModel)
      {[], quote(do: MyModel)}

      iex> escape(quote do: p in posts)
      {[p: 0], quote(do: posts)}

      iex> escape(quote do: p in {"posts", MyModel})
      {[p: 0], quote(do: {"posts", MyModel})}

      iex> escape(quote do: [p, q] in posts)
      {[p: 0, q: 1], quote(do: posts)}

      iex> escape(quote do: [_, _] in abc)
      {[_: 0, _: 1], quote(do: abc)}

      iex> escape(quote do: other)
      {[], quote(do: other)}

      iex> escape(quote do: x() in other)
      ** (Ecto.Query.CompileError) binding list should contain only variables, got: x()

  """
  @spec escape(Macro.t) :: {Keyword.t, Macro.t}
  def escape({:in, _, [var, expr]}) do
    {Builder.escape_binding(List.wrap(var)), expr}
  end

  def escape(expr) do
    {[], expr}
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, Macro.Env.t) :: {Macro.t, Keyword.t, non_neg_integer | nil}
  def build(expr, env) do
    {binds, expr} = escape(expr)

    {count_bind, quoted} =
      case Macro.expand(expr, env) do
        model when is_atom(model) ->
          # Get the source at runtime so no unnecessary compile time
          # dependencies between modules are added
          source = quote do: unquote(model).__schema__(:source)
          {1, query(source, model)}

        source when is_binary(source) ->
          # When a binary is used, there is no model
          {1, query(source, nil)}

        {source, model} when is_binary(source) ->
          {1, query(source, model)}

        other ->
          {nil, other}
      end

    quoted = Builder.apply_query(quoted, __MODULE__, [length(binds)], env)
    {quoted, binds, count_bind}
  end

  defp query(source, model) do
    {:%, [], [Ecto.Query, {:%{}, [], [from: {source, model}]}]}
  end

  @doc """
  The callback applied by `build/2` to build the query.
  """
  @spec apply(Ecto.Queryable.t, non_neg_integer) :: Ecto.Query.t
  def apply(query, binds) do
    query = Ecto.Queryable.to_query(query)
    check_binds(query, binds)
    query
  end

  defp check_binds(query, count) do
    if count > 1 and count > Builder.count_binds(query) do
      Builder.error! "`from` in query expression specified #{count} " <>
                     "binds but query contains #{Builder.count_binds(query)} binds"
    end
  end
end
