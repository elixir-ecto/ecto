defmodule Ecto.Query.FromBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  @doc """
  Handles from expressions.

  The expressions may either contain an `in` expression or not.
  The right side is always expected to Queryable.

  ## Examples

      iex> escape(quote do: MyModel)
      {[], quote(do: MyModel)}

      iex> escape(quote do: p in posts)
      {[p: 0], quote(do: posts)}

      iex> escape(quote do: [p, q] in posts)
      {[p: 0, q: 1], quote(do: posts)}

      iex> escape(quote do: [_, _] in abc)
      {[], quote(do: abc)}

      iex> escape(quote do: other)
      {[], quote(do: other)}

      iex> escape(quote do: x() in other)
      ** (Ecto.QueryError) invalid `from` query expression

  """
  @spec escape(Macro.t) :: {Keyword.t, Macro.t}
  def escape({:in, _, [list, expr]}) when is_list(list) do
    binds =
      Enum.flat_map(Stream.with_index(list), fn
        {{:_, _, context}, _ix} when is_atom(context) ->
          []
        {{var, _, context}, ix} when is_atom(var) and is_atom(context) ->
          [{var, ix}]
        {_, _count} ->
          raise Ecto.QueryError, reason: "invalid `from` query expression"
      end)

    {binds, expr}
  end

  def escape({:in, meta, [var, expr]}) do
    escape({:in, meta, [[var], expr]})
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
  @spec build_with_binds(Macro.t, Macro.Env.t) :: {Macro.t, Keyword.t, non_neg_integer | nil}
  def build_with_binds(expr, env) do
    {binds, expr} = escape(expr)

    case Macro.expand(expr, env) do
      atom when is_atom(atom) ->
        count_bind = 1
        if Code.ensure_compiled?(atom) do
          quoted = Ecto.Queryable.to_query(atom) |> Macro.escape
        else
          quoted = atom
        end
      other ->
        count_bind = nil
        quoted = other
    end

    quoted = BuilderUtil.apply_query(quoted, __MODULE__, [length(binds)], env)
    {quoted, binds, count_bind}
  end

  @doc """
  The callback applied by `build_with_binds/2` to build the query.
  """
  @spec apply(Ecto.Queryable.t, non_neg_integer) :: Ecto.Query.t
  def apply(query, binds) do
    query = Ecto.Queryable.to_query(query)
    check_binds(query, binds)
    query
  end

  defp check_binds(query, count) do
    if count > 1 and count > BuilderUtil.count_binds(query) do
      raise Ecto.QueryError,
        reason: "`from` in query expression specified #{count} " <>
                "binds but query contains #{BuilderUtil.count_binds(query)} binds"
    end
  end
end
