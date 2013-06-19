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
      bind = binding(unquote(vars), true)
      Ecto.Query.merge(unquote(query), :select, unquote(expr), bind)
    end
  end

  defmacro where(query, expr) do
    vars = get_vars(expr)
    expr = Macro.escape(expr)
    quote do
      bind = binding(unquote(vars), true)
      Ecto.Query.merge(unquote(query), :where, unquote(expr), bind)
    end
  end

  def merge(left, right) do
    # TODO: Do sanity checking here
    Query[ froms: left.froms ++ right.froms,
           wheres: left.wheres ++ right.wheres,
           select: right.select ]
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

  def get_vars(ast), do: get_vars(ast, [])

  def get_vars({ var, _, scope }, acc) when is_atom(var) and is_atom(scope) do
    [{ var, scope }|acc]
  end

  def get_vars({ left, _, right }, acc) do
    get_vars(right, get_vars(left, acc))
  end

  def get_vars({ left, right }, acc) do
    get_vars(right, get_vars(left, acc))
  end

  def get_vars(list, acc) when is_list(list) do
    Enum.reduce list, acc, get_vars(&1, &2)
  end

  def get_vars(_, acc), do: acc
end
