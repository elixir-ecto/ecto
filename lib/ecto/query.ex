defmodule Ecto.Query do

  defrecord Query, froms: [], wheres: [], select: nil
  defrecord QueryExpr, [:expr, :binding]

  # :!, :@, :^, :not, :+, :-

  defmacro unary_ops do
    [ :!, :+, :- ]
  end

  # :===, :!==,
  # :==, :!=, :<=, :>=,
  # :&&, :||, :<>, :++, :--, :**, ://, :::, :<-, :.., :|>, :=~,
  # :<, :>, :->,
  # :+, :-, :*, :/, :=, :|, :.,
  # :and, :or, :xor, :when, :in, :inlist, :inbits,
  # :<<<, :>>>, :|||, :&&&, :^^^, :~~~

  defmacro binary_ops do
    [ :==, :!=, :<=, :>=, :&&, :||, :<, :>, :+, :-, :*, :/ ]
  end

  defmacro from(query // Macro.escape(Query[]), expr) do
    expr = expand_in(expr, __CALLER__) |> Macro.escape
    quote do
      Ecto.Query.merge(unquote(query), :from, unquote(expr), [])
    end
  end

  defmacro select(query, expr) do
    vars = get_vars(expr)
    expr = Macro.escape(expr)
    quote do
      bind = binding(unquote(vars))
      Ecto.Query.merge(unquote(query), :select, unquote(expr), bind)
    end
  end

  defmacro where(query, expr) do
    vars = get_vars(expr)
    expr = Macro.escape(expr)
    quote do
      bind = binding(unquote(vars))
      Ecto.Query.merge(unquote(query), :where, unquote(expr), bind)
    end
  end

  def merge(left, right) do
    # TODO: Do sanity checking here
    Query[ froms: left.froms ++ right.froms,
           wheres: left.wheres ++ right.wheres,
           select: right.select || left.select ]
  end

  @doc false
  def merge(query, type, expr, binding) do
    query_expr = QueryExpr[expr: expr, binding: binding]
    query_right = case type do
      :from   -> Query[froms: [query_expr]]
      :where  -> Query[wheres: [query_expr]]
      :select -> Query[select: query_expr]
    end
    merge(query, query_right)
  end

  defp expand_in({ :in, meta, [left, right] }, env) do
    right = Macro.expand(right, env)
    { :in, meta, [left, right] }
  end

  defp get_vars({ :"{}", _, list }) do
    Enum.map(list, get_vars(&1)) |> List.concat
  end

  defp get_vars({ left, right }) do
    get_vars({ :"{}", [], [left, right] })
  end

  defp get_vars(list) when is_list(list) do
    Enum.map(list, get_vars(&1)) |> List.concat
  end

  defp get_vars({ op, _, [arg] }) when op in unary_ops do
    get_vars(arg)
  end

  defp get_vars({ op, _, [left, right] }) when op in binary_ops do
    get_vars(left) ++ get_vars(right)
  end

  defp get_vars({ :., _, [left, _right] }) do
    [left]
  end

  defp get_vars({ ast, _, [] }), do: get_vars(ast)

  defp get_vars({ var, _, atom }) when is_atom(atom) do
    [var]
  end

  defp get_vars(atom) when is_atom(atom), do: [atom]

  defp get_vars(_), do: []
end
