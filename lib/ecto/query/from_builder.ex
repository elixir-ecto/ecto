defmodule Ecto.Query.FromBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  @doc """
  Handles from expressions.

  The expressions may either contain an `in` expression or not.
  The right side is always expected to Queryable.

  ## Examples

      iex> escape(quote do: MyModel)
      { [:_], quote(do: MyModel) }

      iex> escape(quote do: p in posts)
      { [:p], quote(do: posts) }

      iex> escape(quote do: [p, q] in posts)
      { [:p, :q], quote(do: posts) }

      iex> escape(quote do: [_, _] in abc)
      { [:_, :_], quote(do: abc) }

      iex> escape(quote do: other)
      { [:_], quote(do: other) }

      iex> escape(quote do: x() in other)
      ** (Ecto.QueryError) invalid `from` query expression

  """
  @spec escape(Macro.t) :: { [atom], Macro.t }
  def escape({ :in, _, [list, expr] }) when is_list(list) do
    binds = Enum.map(list, fn
      { var, _, context } when is_atom(var) and is_atom(context) ->
        var
      _ ->
        raise Ecto.QueryError, reason: "invalid `from` query expression"
    end)
    { binds, expr }
  end

  def escape({ :in, meta, [var, expr] }) do
    escape({ :in, meta, [[var], expr] })
  end

  def escape(expr) do
    { [:_], expr }
  end

  @doc """
  Builds a quoted expression that will evaluate to a query
  at runtime. If possible, it does all calculations at compile
  time to avoid runtime work.
  """
  @spec build(Macro.t, Macro.Env.t) :: Macro.t
  def build(expr, env) do
    { binds, expr } = escape(expr)

    query = case Macro.expand(expr, env) do
      atom when is_atom(atom) ->
        if Code.ensure_compiled?(atom) do
          Ecto.Queryable.to_query(atom) |> Macro.escape
        else
          atom
        end
      other -> other
    end

    BuilderUtil.apply_query(query, __MODULE__, [length(binds)], env)
  end

  @doc """
  The callback invoked at runtime to build the query.
  """
  @spec apply(Ecto.Queryable.t, non_neg_integer) :: Ecto.Query.Query.t
  def apply(query, binds) do
    query = Ecto.Queryable.to_query(query)
    check_binds(query, binds)
    query
  end

  defp check_binds(query, count) do
    if count > 1 and count > Ecto.Query.Util.count_binds(query) do
      raise Ecto.QueryError,
        reason: "`from` in query expression specified #{count} " <>
                "binds but query contains #{Ecto.Query.Util.count_binds(query)} binds"
    end
  end
end
