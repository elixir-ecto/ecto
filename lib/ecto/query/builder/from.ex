defmodule Ecto.Query.Builder.From do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Handles from expressions.

  The expressions may either contain an `in` expression or not.
  The right side is always expected to Queryable.

  ## Examples

      iex> escape(quote do: MySchema)
      {quote(do: MySchema), []}

      iex> escape(quote do: p in posts)
      {quote(do: posts), [p: 0]}

      iex> escape(quote do: p in {"posts", MySchema})
      {quote(do: {"posts", MySchema}), [p: 0]}

      iex> escape(quote do: [p, q] in posts)
      {quote(do: posts), [p: 0, q: 1]}

      iex> escape(quote do: [_, _] in abc)
      {quote(do: abc), [_: 0, _: 1]}

      iex> escape(quote do: other)
      {quote(do: other), []}

      iex> escape(quote do: x() in other)
      ** (Ecto.Query.CompileError) binding list should contain only variables, got: x()

  """
  @spec escape(Macro.t) :: {Macro.t, Keyword.t}
  def escape({:in, _, [var, query]}) do
    Builder.escape_binding(query, List.wrap(var))
  end

  def escape(query) do
    {query, []}
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, Macro.Env.t) :: {Macro.t, Keyword.t, non_neg_integer | nil}
  def build(query, env) do
    {query, binds} = escape(query)

    {count_bind, quoted} =
      case expand_from(query, env) do
        schema when is_atom(schema) ->
          # Get the source at runtime so no unnecessary compile time
          # dependencies between modules are added
          source = quote do: unquote(schema).__schema__(:source)
          prefix = quote do: unquote(schema).__schema__(:prefix)
          {1, query(prefix, source, schema)}

        source when is_binary(source) ->
          # When a binary is used, there is no schema
          {1, query(nil, source, nil)}

        {source, schema} when is_binary(source) and is_atom(schema) ->
          prefix = quote do: unquote(schema).__schema__(:prefix)
          {1, query(prefix, source, schema)}

        other ->
          {nil, other}
      end

    quoted = Builder.apply_query(quoted, __MODULE__, [length(binds)], env)
    {quoted, binds, count_bind}
  end

  defp query(prefix, source, schema) do
    {:%, [], [Ecto.Query, {:%{}, [], [from: {source, schema}, prefix: prefix]}]}
  end

  defp expand_from({left, right}, env) do
    {left, Macro.expand(right, env)}
  end
  defp expand_from(other, env) do
    Macro.expand(other, env)
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
