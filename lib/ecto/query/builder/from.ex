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
  @spec escape(Macro.t(), Macro.Env.t()) :: {Macro.t(), Keyword.t()}
  def escape({:in, _, [var, query]}, env) do
    query = escape_source(query, env)
    Builder.escape_binding(query, List.wrap(var), env)
  end

  def escape(query, env) do
    query = escape_source(query, env)
    {query, []}
  end

  defp escape_source({:fragment, _, _} = fragment, env) do
    {fragment, {params, _acc}} = Builder.escape(fragment, :any, {[], %{}}, [], env)
    {fragment, Builder.escape_params(params)}
  end

  defp escape_source(query, _env), do: query
  
  @typep hints :: [String.t() | {atom, term}]

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t(), Macro.Env.t(), atom, {:ok, String.t | nil} | nil, hints) ::
          {Macro.t(), Keyword.t(), non_neg_integer | nil}
  def build(query, env, as, prefix, hints) do
    unless Enum.all?(hints, &is_valid_hint/1) do
      Builder.error!(
        "`hints` must be a compile time string, list of strings, a tuple, or a list of tuples " <>
          "got: `#{Macro.to_string(hints)}`"
      )
    end

    case prefix do
      nil -> :ok
      {:ok, prefix} when is_binary(prefix) or is_nil(prefix) -> :ok
      _ -> Builder.error!("`prefix` must be a compile time string, got: `#{Macro.to_string(prefix)}`")
    end
    
    as = case as do
      {:^, _, [as]} -> as
      as when is_atom(as) -> as
      as -> Builder.error!("`as` must be a compile time atom or an interpolated value using ^, got: #{Macro.to_string(as)}")
    end

    {query, binds} = escape(query, env)

    case expand_from(query, env) do
      schema when is_atom(schema) ->
        # Get the source at runtime so no unnecessary compile time
        # dependencies between modules are added
        source = quote(do: unquote(schema).__schema__(:source))
        {:ok, prefix} = prefix || {:ok, quote(do: unquote(schema).__schema__(:prefix))}
        {query(prefix, {source, schema}, [], as, hints, env.file, env.line), binds, 1}

      source when is_binary(source) ->
        {:ok, prefix} = prefix || {:ok, nil}
        # When a binary is used, there is no schema
        {query(prefix, {source, nil}, [], as, hints, env.file, env.line), binds, 1}

      {source, schema} when is_binary(source) and is_atom(schema) ->
        {:ok, prefix} = prefix || {:ok, quote(do: unquote(schema).__schema__(:prefix))}
        {query(prefix, {source, schema}, [], as, hints, env.file, env.line), binds, 1}

      {{:{}, _, [:fragment, _, _]} = fragment, params} ->
        {:ok, prefix} = prefix || {:ok, nil}
        {query(prefix, fragment, params, as, hints, env.file, env.line), binds, 1}

      _other ->
        quoted =
          quote do
            Ecto.Query.Builder.From.apply(unquote(query), unquote(length(binds)), unquote(as), unquote(prefix), unquote(hints))
          end

        {quoted, binds, nil}
    end
  end

  defp query(prefix, source, params, as, hints, file, line) do
    aliases = if as, do: [{as, 0}], else: []
    from_fields = [source: source, params: params, as: as, prefix: prefix, hints: hints, file: file, line: line]

    query_fields = [
      from: {:%, [], [Ecto.Query.FromExpr, {:%{}, [], from_fields}]},
      aliases: {:%{}, [], aliases}
    ]

    {:%, [], [Ecto.Query, {:%{}, [], query_fields}]}
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
  @spec apply(Ecto.Queryable.t(), non_neg_integer, Macro.t(), {:ok, String.t} | nil, hints) :: Ecto.Query.t()
  def apply(query, binds, as, prefix, hints) do
    query =
      query
      |> Ecto.Queryable.to_query()
      |> maybe_apply_as(as)
      |> maybe_apply_prefix(prefix)
      |> maybe_apply_hints(hints)

    check_binds(query, binds)
    query
  end

  defp maybe_apply_as(query, nil), do: query

  defp maybe_apply_as(%{from: %{as: from_as}}, as) when not is_nil(from_as) do
    Builder.error!(
      "can't apply alias `#{inspect(as)}`, binding in `from` is already aliased to `#{inspect(from_as)}`"
    )
  end

  defp maybe_apply_as(%{from: from, aliases: aliases} = query, as) do
    if Map.has_key?(aliases, as) do
      Builder.error!("alias `#{inspect(as)}` already exists")
    else
      %{query | aliases: Map.put(aliases, as, 0), from: %{from | as: as}}
    end
  end

  defp maybe_apply_prefix(query, nil), do: query

  defp maybe_apply_prefix(query, {:ok, prefix}) do
    update_in query.from.prefix, fn
      nil ->
        prefix

      from_prefix ->
        Builder.error!(
          "can't apply prefix `#{inspect(prefix)}`, `from` is already prefixed to `#{inspect(from_prefix)}`"
        )
    end
  end

  defp maybe_apply_hints(query, []), do: query
  defp maybe_apply_hints(query, hints), do: update_in(query.from.hints, &(&1 ++ hints))

  defp is_valid_hint(hint) when is_binary(hint), do: true
  defp is_valid_hint({_key, _val}), do: true
  defp is_valid_hint(_), do: false

  defp check_binds(query, count) do
    if count > 1 and count > Builder.count_binds(query) do
      Builder.error!(
        "`from` in query expression specified #{count} " <>
          "binds but query contains #{Builder.count_binds(query)} binds"
      )
    end
  end
end
