defmodule Ecto.Query do

  defrecord QueryBuilder, exprs: []

  defrecord Query, froms: [], wheres: [], select: nil

  def normalize(query) do
    exprs = Enum.reverse(query.exprs)

    unless match?({:from, _}, Enum.first(exprs)), do: throw :normalize_error

    Enum.reduce(exprs, Query[], fn(expr, q) ->
      unless !q.select, do: throw :normalize_error
      case expr do
        { :from, expr } ->
          q.update_froms(&1 ++ [expr])
        { :where, expr } ->
          q.update_wheres(&1 ++ [expr])
        { :select, expr } ->
          q.select(expr)
      end
    end)
  end
end

defmodule Ecto.Query.DSL do

  defmacro from(expr) do
    query = Ecto.Query.QueryBuilder[]
    expr = Macro.escape(expr)
    quote do
      unquote(query).exprs([from: unquote(expr)])
    end
  end

  defmacro from(query, expr) do
    expr = Macro.escape(expr)
    quote do
      unquote(query).update_exprs([from: unquote(expr)] ++ &1)
    end
  end

  defmacro select(query, expr) do
    expr = Macro.escape(expr)
    quote do
      unquote(query).update_exprs([select: unquote(expr)] ++ &1)
    end
  end

  defmacro where(query, expr) do
    expr = Macro.escape(expr)
    quote do
      unquote(query).update_exprs([where: unquote(expr)] ++ &1)
    end
  end

  defp to_query({ :in, _, [_, { :__aliases__, _, _} = module] }, env) do
    quote do
      Ecto.Query.QueryBuilder[repo: unquote(Macro.expand(module, env))]
    end
  end

  defp to_query(query, _env) do
    query
  end
end
