defmodule Ecto.SQL do

  require Ecto.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.BuilderUtil

  binary_ops =
    [ ==: "=", !=: "!=", <=: "<=", >=: ">=", <:  "<", >:  ">",
      &&: "AND", ||: "OR",
      +:  "+", -:  "-", *:  "*", /:  "/" ]

  @binary_ops Dict.keys(binary_ops)

  Enum.map(binary_ops, fn { op, str } ->
    defp binop_to_binary(unquote(op)), do: unquote(str)
  end)

  # TODO: Use binding and vars when generating SQL

  def compile(query) do
    gen_sql(query)
  end

  defp gen_sql(query) do
    Ecto.Query.validate(query)

    select = gen_select(query.select, query.froms)
    from = gen_from(query.froms)
    where = gen_where(query.wheres, query.froms)

    list = [select, from, where] |> Enum.filter(fn x -> x != nil end)
    Enum.join(list, "\n")
  end

  defp gen_select(expr, vars) do
    { _, clause } = expr.expr
    vars = BuilderUtil.merge_binding_vars(expr.binding, vars)
    "SELECT " <> select_clause(clause, vars)
  end

  defp gen_from(froms) do
    binds = Enum.map_join(froms, ", ", fn({ var, record }) ->
      var = atom_to_binary(var)
      table = Module.split(record) |> List.last |> String.downcase
      "#{table} AS #{var}"
    end)

    "FROM " <> binds
  end

  defp gen_where([], _vars), do: nil

  defp gen_where(wheres, vars) do
    exprs = Enum.map_join(wheres, " AND ", fn(expr) ->
      rebound_vars = BuilderUtil.merge_binding_vars(expr.binding, vars)
      "(" <> gen_expr(expr.expr, rebound_vars) <> ")"
    end)

    "WHERE " <> exprs
  end

  defp gen_expr({ expr, _, [] }, vars) do
    gen_expr(expr, vars)
  end

  defp gen_expr({ :., _, [{ var, _, context }, field] }, vars)
      when is_atom(var) and is_atom(context) and is_atom(field) do
    { var, _ } = Keyword.fetch!(vars, var)
    "#{var}.#{field}"
  end

  defp gen_expr({ :!, _, [expr] }, vars) do
    "NOT (" <> gen_expr(expr, vars) <> ")"
  end

  # Expression builders make sure that we only find undotted vars at the top level
  defp gen_expr({ var, _, context }, vars) when is_atom(var) and is_atom(context) do
    { var, entity } = Keyword.fetch!(vars, var)
    fields = entity.__ecto__(:field_names)
    Enum.map_join(fields, ", ", fn(field) -> "#{var}.#{field}" end)
  end

  defp gen_expr({ op, _, [expr] }, vars) when op in [:+, :-] do
    atom_to_binary(op) <> gen_expr(expr, vars)
  end

  defp gen_expr({ :==, _, [nil, right] }, vars) do
    "#{op_to_binary(right, vars)} IS NULL"
  end

  defp gen_expr({ :==, _, [left, nil] }, vars) do
    "#{op_to_binary(left, vars)} IS NULL"
  end

  defp gen_expr({ :!=, _, [nil, right] }, vars) do
    "#{op_to_binary(right, vars)} IS NOT NULL"
  end

  defp gen_expr({ :!=, _, [left, nil] }, vars) do
    "#{op_to_binary(left, vars)} IS NOT NULL"
  end

  defp gen_expr({ op, _, [left, right] }, vars) when op in @binary_ops do
    "#{op_to_binary(left, vars)} #{binop_to_binary(op)} #{op_to_binary(right, vars)}"
  end

  defp gen_expr(literal, _vars), do: gen_literal(literal)

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

  defp op_to_binary({ op, _, [_, _] } = expr, vars) when op in @binary_ops do
    "(" <> gen_expr(expr, vars) <> ")"
  end

  defp op_to_binary(expr, vars) do
    gen_expr(expr, vars)
  end

  # TODO: Records (Kernel.access)
  defp select_clause({ :{}, _, elems }, vars) do
    Enum.map_join(elems, ", ", select_clause(&1, vars))
  end

  defp select_clause({ x, y }, vars) do
    select_clause({ :{}, [], [x, y] }, vars)
  end

  defp select_clause(list, vars) when is_list(list) do
    Enum.map_join(list, ", ", select_clause(&1, vars))
  end

  defp select_clause(expr, vars) do
    gen_expr(expr, vars)
  end

  defp escape_string(value) when is_binary(value) do
    value
      |> :binary.replace("\\", "\\\\", [:global])
      |> :binary.replace("'", "''", [:global])
  end
end
