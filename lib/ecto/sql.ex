defmodule Ecto.SQL do

  require Ecto.Query
  alias Ecto.Query.QueryExpr

  binary_ops =
    [ ==: "=", !=: "!=", <=: "<=", >=: ">=", <:  "<", >:  ">",
      &&: "AND", ||: "OR",
      +:  "+", -:  "-", *:  "*", /:  "/" ]

  Enum.map(binary_ops, fn { op, str } ->
    def binop_to_binary(unquote(op)), do: unquote(str)
  end)

  def compile(query) do
    gen_sql(query)
  end

  defp gen_sql(query) do
    select = gen_select(query.select)
    from = gen_from(query.froms)
    where = unless query.wheres == [], do: gen_where(query.wheres)

    list = [select, from, where] |> Enum.filter(fn x -> x != nil end)
    Enum.join(list, "\n")
  end

  defp gen_select(QueryExpr[expr: expr, binding: bind]) do
    "SELECT " <> select_clause(expr, bind)
  end

  defp gen_from(froms) do
    binds = Enum.map_join(froms, ", ", fn(QueryExpr[expr: expr, binding: []]) ->
      { :in, _, [{var, _, _}, module] } = expr
      var = atom_to_binary(var)
      module = Macro.expand(module, __ENV__)
      table = Module.split(module) |> List.last |> String.downcase
      "#{table} AS #{var}"
    end)

    "FROM " <> binds
  end

  defp gen_where(wheres) do
    exprs = Enum.map_join(wheres, " AND ", fn(QueryExpr[expr: expr, binding: bind]) ->
      "(#{gen_expr(expr, bind)})"
    end)

    "WHERE " <> exprs
  end

  defp gen_expr({ expr, _, [] }, bind) do
    gen_expr(expr, bind)
  end

  defp gen_expr({ :., _, [left, right] }, bind) do
    "#{gen_expr(left, bind)}.#{gen_expr(right, bind)}"
  end

  defp gen_expr({ :!, _, [expr] }, bind) do
    "NOT " <> gen_expr(expr, bind)
  end

  defp gen_expr({ op, _, [expr] }, bind) when op in [:+, :-] do
    atom_to_binary(op) <> gen_expr(expr, bind)
  end

  defp gen_expr({ op, _, [left, right] }, bind) when op in Ecto.Query.binary_ops do
    "#{op_to_binary(left, bind)} #{binop_to_binary(op)} #{op_to_binary(right, bind)}"
  end

  defp gen_expr({ var, _, atom }, bind) when is_atom(atom) do
    to_binary(bind[var] || var)
  end

  defp gen_expr(nil, _bind) do
    "NULL"
  end

  defp gen_expr(atom, bind) when is_atom(atom) do
    to_binary(bind[atom] || atom)
  end

  defp gen_expr(expr, _bind) do
    to_binary(expr)
  end

  defp op_to_binary({ op, _, [_, _] } = expr, bind) when op in Ecto.Query.binary_ops do
    "(" <> gen_expr(expr, bind) <> ")"
  end

  defp op_to_binary(expr, bind) do
    gen_expr(expr, bind)
  end

  # TODO: Records (Kernel.access)
  defp select_clause({ :"{}", _, elems }, bind) do
    Enum.map_join(elems, ", ", select_clause(&1, bind))
  end

  defp select_clause({ x, y }, bind) do
    select_clause({ :"{}", [], [x, y] }, bind)
  end

  defp select_clause(list, bind) when is_list(list) do
    Enum.map_join(list, ", ", select_clause(&1, bind))
  end

  defp select_clause(expr, bind) do
    gen_expr(expr, bind)
  end
end
