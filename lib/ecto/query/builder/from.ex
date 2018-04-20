defmodule Ecto.Query.Builder.From do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Handles from expressions.

  The expressions may either contain an `in` expression or not.
  The right side is always expected to Queryable.

  ## Examples

      iex> escape(quote(do: MySchema), __ENV__)
      {quote(do: MySchema), []}

      iex> escape(quote(do: p in posts), __ENV__)
      {quote(do: posts), [p: 0]}

      iex> escape(quote(do: p in {"posts", MySchema}), __ENV__)
      {quote(do: {"posts", MySchema}), [p: 0]}

      iex> escape(quote(do: [p, q] in posts), __ENV__)
      {quote(do: posts), [p: 0, q: 1]}

      iex> escape(quote(do: [_, _] in abc), __ENV__)
      {quote(do: abc), [_: 0, _: 1]}

      iex> escape(quote(do: other), __ENV__)
      {quote(do: other), []}

      iex> escape(quote(do: x() in other), __ENV__)
      ** (Ecto.Query.CompileError) binding list should contain only variables or `{as, var}` tuples, got: x()

  """
  @spec escape(Macro.t, Macro.Env.t) :: {Macro.t, Keyword.t}
  def escape({:in, _, [var, query]}, env) do
    Builder.escape_binding(query, List.wrap(var), env)
  end

  def escape(query, _env) do
    {query, []}
  end

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t, Macro.Env.t, atom) :: {Macro.t, Keyword.t, non_neg_integer | nil}
  def build(query, env, as) do
    if not is_atom(as) do
      Builder.error! "`as` must be a compile time atom, got: `#{Macro.to_string(as)}`"
    end

    {query, binds} = escape(query, env)

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

    quoted = Builder.apply_query(quoted, __MODULE__, [length(binds), as], env)
    {quoted, binds, count_bind}
  end

  defp query(prefix, source, schema) do
    {:%, [], [Ecto.Query,
              {:%{}, [],
               [from: {:%, [], [Ecto.Query.FromExpr,
                                {:%{}, [], [source: {source, schema}]}]},
                prefix: prefix,
                aliases: {:%{}, [], []}]}]}
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
  @spec apply(Ecto.Queryable.t, non_neg_integer, atom) :: Ecto.Query.t
  def apply(query, binds, as) do
    query =
      query
      |> Ecto.Queryable.to_query()
      |> maybe_apply_as(as)

    check_binds(query, binds)
    query
  end

  defp maybe_apply_as(query, nil), do: query
  defp maybe_apply_as(query, as) do
    if raw_source?(query) do
      %{from: from, aliases: aliases} = query
      %{query | aliases: Map.put(aliases, as, 0), from: %{from | as: as}}
    else
      query
    end
  end

  defp raw_source?(%{from: %{source: source}}), do: raw_source?(source)
  defp raw_source?({{{:., _, [schema, :__schema__]}, _, [:source]}, schema}), do: true
  defp raw_source?(schema) when is_atom(schema), do: true
  defp raw_source?(source) when is_binary(source), do: true
  defp raw_source?({source, schema}) when is_binary(source) and is_atom(schema), do: true
  defp raw_source?(_), do: false

  defp check_binds(query, count) do
    if count > 1 and count > Builder.count_binds(query) do
      Builder.error! "`from` in query expression specified #{count} " <>
                     "binds but query contains #{Builder.count_binds(query)} binds"
    end
  end
end
