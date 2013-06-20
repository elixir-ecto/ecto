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
    Ecto.Query.validate(query)

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
    case bind[{ var, atom }] do
      nil -> gen_literal(var)
      val -> gen_literal(val)
    end
  end

  defp gen_expr(atom, _bind) when is_atom(atom) do
    gen_literal(atom)
  end

  defp gen_expr(literal, _bind), do: gen_literal(literal)

  defp gen_literal(nil), do: "NULL"

  defp gen_literal(literal) when is_binary(literal) do
    "'#{escape_string(literal)}'"
  end

  defp gen_literal(literal) when is_list(literal) do
    gen_literal(:unicode.characters_to_binary(literal))
  end

  defp gen_literal(literal), do: to_binary(literal)

  # TODO: Make sure that Elixir's to_binary for numbers is compatible with PG
  # http://www.postgresql.org/docs/9.2/interactive/sql-syntax-lexical.html

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

  defp escape_string(value) when is_binary(value) do
    value
      |> :binary.replace("\\", "\\\\", [:global])
      |> :binary.replace("'", "''", [:global])
  end
end
