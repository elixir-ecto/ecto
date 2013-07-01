defmodule Ecto.Query do

  defrecord Query, froms: [], wheres: [], select: nil

  alias Ecto.Query.FromBuilder
  alias Ecto.Query.WhereBuilder
  alias Ecto.Query.SelectBuilder

  defmacro from(query // Macro.escape(Query[]), expr) do
    quote do
      from_expr = unquote(FromBuilder.escape(expr))
      Ecto.Query.merge(unquote(query), :from, from_expr)
    end
  end

  defmacro select(query // Macro.escape(Query[]), binding, expr)
      when is_list(binding) do
    binding = Enum.map(binding, escape_binding(&1))
    quote do
      select_expr = unquote(SelectBuilder.escape(expr, binding))
      Ecto.Query.merge(unquote(query), :select, select_expr)
    end
  end

  defmacro where(query // Macro.escape(Query[]), binding, expr)
      when is_list(binding) do
    binding = Enum.map(binding, escape_binding(&1))
    quote do
      where_expr = unquote(WhereBuilder.escape(expr, binding))
      Ecto.Query.merge(unquote(query), :where, where_expr)
    end
  end

  def merge(left, right) do
    check_merge(left, right)

    Query[ froms: left.froms ++ right.froms,
           wheres: left.wheres ++ right.wheres,
           select: right.select ]
  end

  @doc false
  def merge(query, type, expr) do
    check_merge(query, Query.new([{ type, expr }]))

    case type do
      :from   -> query.update_froms(&1 ++ [expr])
      :where  -> query.update_wheres(&1 ++ [expr])
      :select -> query.select(expr)
    end
  end

  def validate(query) do
    Ecto.Query.Validator.validate(query)
  end

  defp check_merge(left, _right) do
    if left.select do
      raise ArgumentError, message: "cannot append to query where result is selected"
    end
  end

  defp escape_binding(list) when is_list(list) do
    escape_binding(list)
  end

  defp escape_binding({ var, _, context }) when is_atom(var) and is_atom(context) do
    var
  end

  defp escape_binding(_) do
    raise ArgumentError, message: "binding should be list of variables"
  end
end
