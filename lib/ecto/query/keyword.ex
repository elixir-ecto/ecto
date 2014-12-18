defmodule Ecto.Query.Keyword do
  @moduledoc false

  # Builds the quoted code for creating a keyword query

  alias Ecto.Query.Builder

  @binds    [:where, :select, :distinct, :order_by, :group_by, :having, :limit, :offset]
  @no_binds [:preload, :lock]
  @joins    [:join, :inner_join, :left_join, :right_join, :full_join]

  def build([{type, expr}|t], env, count_bind, quoted, binds) when type in @binds do
    # If all bindings are integer indexes keep AST Macro.expand'able to %Query{},
    # otherwise ensure that quoted is evaluated before macro call
    quoted =
      if Enum.all?(binds, fn {_, value} -> is_integer(value) end) do
        quote do
          Ecto.Query.unquote(type)(unquote(quoted), unquote(binds), unquote(expr))
        end
      else
        quote do
          query = unquote(quoted)
          Ecto.Query.unquote(type)(query, unquote(binds), unquote(expr))
        end
      end

    build(t, env, count_bind, quoted, binds)
  end

  def build([{type, expr}|t], env, count_bind, quoted, binds) when type in @no_binds do
    quoted =
      quote do
        Ecto.Query.unquote(type)(unquote(quoted), unquote(expr))
      end

    build(t, env, count_bind, quoted, binds)
  end

  def build([{join, expr}|t], env, count_bind, quoted, binds) when join in @joins do
    qual =
      case join do
        :join       -> :inner
        :inner_join -> :inner
        :left_join  -> :left
        :right_join -> :right
        :full_join  -> :full
      end

    {t, on} = collect_on(t, nil)
    {quoted, binds, count_bind} = Builder.Join.build(quoted, qual, binds, expr, on, count_bind, env)
    build(t, env, count_bind, quoted, binds)
  end

  def build([{:on, _value}|_], _env, _count_bind, _quoted, _binds) do
    Builder.error! "`on` keyword must immediately follow a join"
  end

  def build([{key, _value}|_], _env, _count_bind, _quoted, _binds) do
    Builder.error! "unsupported #{inspect key} in keyword query expression"
  end

  def build([], _env, _count_bind, quoted, _binds) do
    quoted
  end

  defp collect_on([{:on, expr}|t], nil),
    do: collect_on(t, expr)
  defp collect_on([{:on, expr}|t], acc),
    do: collect_on(t, {:and, [], [acc, expr]})
  defp collect_on(other, acc),
    do: {other, acc}
end
