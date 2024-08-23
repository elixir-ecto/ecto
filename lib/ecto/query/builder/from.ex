defmodule Ecto.Query.Builder.From do
  @moduledoc false

  alias Ecto.Query.Builder

  @doc """
  Handles from expressions.

  The expressions may either contain an `in` expression or not.
  The right side is always expected to Queryable.

  ## Examples

      iex> escape(quote(do: MySchema), __ENV__)
      {MySchema, []}

      iex> escape(quote(do: p in posts), __ENV__)
      {quote(do: posts), [p: 0]}

      iex> escape(quote(do: p in {"posts", MySchema}), __ENV__)
      {{"posts", MySchema}, [p: 0]}

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

  defp escape_source(query, env) do
    case Macro.expand_once(query, env) do
      {:fragment, _, _} = fragment ->
        {fragment, {params, _acc}} = Builder.escape(fragment, :any, {[], %{}}, [], env)
        {fragment, Builder.escape_params(params)}

      {:values, _, [values_list, types]} ->
        prelude = quote do: values = Ecto.Query.Values.new(unquote(values_list), unquote(types))
        types = quote do: values.types
        num_rows = quote do: values.num_rows
        params = quote do: Ecto.Query.Builder.escape_params(values.params)
        {{:{}, [], [:values, [], [types, num_rows]]}, prelude, params}

      ^query ->
        case query do
          {left, right} -> {left, Macro.expand(right, env)}
          _ -> query
        end

      other ->
        escape_source(other, env)
    end
  end

  @typep hints :: [String.t() | Macro.t()]

  @doc """
  Builds a quoted expression.

  The quoted expression should evaluate to a query at runtime.
  If possible, it does all calculations at compile time to avoid
  runtime work.
  """
  @spec build(Macro.t(), Macro.Env.t(), atom, {:ok, Ecto.Schema.prefix | nil} | nil, hints) ::
          {Macro.t(), Keyword.t(), non_neg_integer | nil}
  def build(query, env, as, prefix, hints) do
    hints = Enum.map(hints, &hint!(&1))

    prefix = case prefix do
      nil -> nil
      {:ok, prefix} when is_binary(prefix) or is_nil(prefix) -> {:ok, prefix}
      {:ok, {:^, _, [prefix]}} -> {:ok, prefix}
      {:ok, prefix} -> Builder.error!("`prefix` must be a compile time string or an interpolated value using ^, got: #{Macro.to_string(prefix)}")
    end

    as = case as do
      {:^, _, [as]} -> as
      as when is_atom(as) -> as
      as -> Builder.error!("`as` must be a compile time atom or an interpolated value using ^, got: #{Macro.to_string(as)}")
    end

    {query, binds} = escape(query, env)

    case query do
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

      {{:{}, _, [:values, _, _]} = values, prelude, params} ->
        {:ok, prefix} = prefix || {:ok, nil}
        query = query(prefix, values, params, as, hints, env.file, env.line)

        quoted =
          quote do
            unquote(prelude)
            unquote(query)
          end

        {quoted, binds, 1}

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

  @doc """
  Validates hints at compile time and runtime
  """
  def hint!(hint) when is_binary(hint), do: hint

  def hint!({:unsafe_fragment, _, [fragment]}) do
    case fragment do
      {:^, _, [value]} ->
        quote do: Ecto.Query.Builder.From.hint!(unquote(value))

      _ ->
        Builder.error!(
          "`unsafe_fragment/1` in `hints` expects an interpolated value, such as " <>
            "unsafe_fragment(^value), got: `#{Macro.to_string(fragment)}`"
        )
    end
  end

  def hint!(other) do
    Builder.error!(
      "`hints` must be a compile time string, unsafe fragment of the form `unsafe_fragment(^...)`, " <>
        "or list containing either, got: `#{Macro.to_string(other)}`"
    )
  end

  @doc """
  The callback applied by `build/2` to build the query.
  """
  @spec apply(Ecto.Queryable.t(), non_neg_integer, Macro.t(), {:ok, Ecto.Schema.prefix} | nil, hints) :: Ecto.Query.t()
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

  defp check_binds(query, count) do
    if count > 1 and count > Builder.count_binds(query) do
      Builder.error!(
        "`from` in query expression specified #{count} " <>
          "binds but query contains #{Builder.count_binds(query)} binds"
      )
    end
  end
end
