defmodule Ecto.Query.FromBuilder do
  @moduledoc false

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
      ** (Ecto.InvalidQueryError) invalid `from` query expression

  """
  @spec escape(Macro.t) :: { [atom], Macro.t }
  def escape({ :in, _, [list, expr] }) when is_list(list) do
    binds = Enum.map(list, fn
      { var, _, context } when is_atom(var) and is_atom(context) ->
        var
      _ ->
        raise Ecto.InvalidQueryError, reason: "invalid `from` query expression"
    end)
    { binds, expr }
  end

  def escape({ :in, meta, [var, expr] }) do
    escape({ :in, meta, [[var], expr] })
  end

  def escape(expr) do
    { [:_], expr }
  end
end
