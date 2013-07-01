defmodule Ecto.SQL do

  require Ecto.Query
  alias Ecto.Query.QueryExpr

  # TODO: Figure out when we have to add parenthesis and when we dont.
  #       Should we always do it as soon as we have a nested expression
  #       and never when it's a single literal?
  # WHERE (x) AND (y), NOT (x),

  @binary_ops [ :==, :!=, :<=, :>=, :and, :or, :<, :>, :+, :-, :*, :/ ]

  binary_ops =
    [ ==: "=", !=: "!=", <=: "<=", >=: ">=", <:  "<", >:  ">",
      &&: "AND", ||: "OR",
      +:  "+", -:  "-", *:  "*", /:  "/" ]

  Enum.map(binary_ops, fn { op, str } ->
    defp binop_to_binary(unquote(op)), do: unquote(str)
  end)

  def compile(query) do
    gen_sql(query)
  end

  defp gen_sql(query) do
    Ecto.Query.validate(query)

    select = gen_select(query.select)
    from = gen_from(query.froms)
    where = gen_where(query.wheres)

    list = [select, from, where] |> Enum.filter(fn x -> x != nil end)
    Enum.join(list, "\n")
  end

  defp gen_select({ _type, expr }) do
    "SELECT " <> select_clause(expr)
  end

  defp gen_from(froms) do
    binds = Enum.map_join(froms, ", ", fn({ var, record }) ->
      var = atom_to_binary(var)
      table = Module.split(record) |> List.last |> String.downcase
      "#{table} AS #{var}"
    end)

    "FROM " <> binds
  end

  defp gen_where([]), do: nil

  defp gen_where(wheres) do
    exprs = Enum.map_join(wheres, " AND ", fn(expr) ->
      "(" <> gen_expr(expr) <> ")"
    end)

    "WHERE " <> exprs
  end

  defp gen_expr({ expr, _, [] }) do
    gen_expr(expr)
  end

  defp gen_expr({ :., _, [left, right] }) do
    "#{gen_expr(left)}.#{gen_expr(right)}"
  end

  # TODO: Translate entity to entity.*

  defp gen_expr({ :!, _, [expr] }) do
    "NOT (" <> gen_expr(expr) <> ")"
  end

  defp gen_expr({ op, _, [expr] }) when op in [:+, :-] do
    atom_to_binary(op) <> gen_expr(expr)
  end

  # TODO: Translate x = nil to x IS NULL and x != nil to x IS NOT NULL
  defp gen_expr({ op, _, [left, right] }) when op in @binary_ops do
    "#{op_to_binary(left)} #{binop_to_binary(op)} #{op_to_binary(right)}"
  end

  defp gen_expr({ var, _, context }) when is_atom(var) and is_atom(context) do
    gen_literal(var)
  end

  defp gen_expr(literal), do: gen_literal(literal)

  defp gen_literal(nil), do: "NULL"

  defp gen_literal(literal) when is_atom(literal) do
    to_binary(literal)
  end

  defp gen_literal(literal) when is_binary(literal) do
    "'#{escape_string(literal)}'"
  end

  defp gen_literal(literal) when is_number(literal) do
    to_binary(literal)
  end

  # TODO: Make sure that Elixir's to_binary for numbers is compatible with PG
  # http://www.postgresql.org/docs/9.2/interactive/sql-syntax-lexical.html

  defp op_to_binary({ op, _, [_, _] } = expr) when op in @binary_ops do
    "(" <> gen_expr(expr) <> ")"
  end

  defp op_to_binary(expr) do
    gen_expr(expr)
  end

  # TODO: Records (Kernel.access)
  defp select_clause({ :{}, _, elems }) do
    Enum.map_join(elems, ", ", select_clause(&1))
  end

  defp select_clause({ x, y }) do
    select_clause({ :{}, [], [x, y] })
  end

  defp select_clause(list) when is_list(list) do
    Enum.map_join(list, ", ", select_clause(&1))
  end

  defp select_clause(expr) do
    gen_expr(expr)
  end

  defp escape_string(value) when is_binary(value) do
    value
      |> :binary.replace("\\", "\\\\", [:global])
      |> :binary.replace("'", "''", [:global])
  end
end
