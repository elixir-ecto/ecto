defmodule Ecto.SQL do

  # :===, :!==,
  # :==, :!=, :<=, :>=,
  # :&&, :||, :<>, :++, :--, :**, ://, :::, :<-, :.., :|>, :=~,
  # :<, :>, :->,
  # :+, :-, :*, :/, :=, :|, :.,
  # :and, :or, :xor, :when, :in, :inlist, :inbits,
  # :<<<, :>>>, :|||, :&&&, :^^^, :~~~

  defmacrop bin_ops do
    [ ==: "=",
      !=: "!=",
      <=: "<=",
      >=: ">=",
      &&: "AND",
      ||: "OR",
      <:  "<",
      >:  ">",
      +:  "+",
      -:  "-",
      *:  "*",
      /:  "/"
    ]
  end

  defmacrop binary_ops_lookup do
    HashDict.new(bin_ops) |> Macro.escape
  end

  defmacrop binary_ops do
    bin_ops |> Dict.keys
  end

  def compile(query) do
    query = Ecto.Query.normalize(query)
    gen_sql(query)
  end

  defp gen_sql(query) do
    select = gen_select(quotify(query.select))
    from = gen_from(query.froms)
    where = unless query.wheres == [], do: gen_where(query.wheres)

    list = [select, from, where] |> Enum.filter(fn x -> x != nil end)
    Enum.join(list, "\n")
  end

  defp gen_select(clause) do
    "SELECT " <> select_clause(clause)
  end

  defp gen_from(froms) do
    binds = Enum.map_join(froms, ", ", fn(from) ->
      { :in, _, [{var, _, _}, module] } = from
      var = atom_to_binary(var)
      module = Macro.expand(module, __ENV__)
      table = Module.split(module) |> List.last |> String.downcase
      "#{table} AS #{var}"
    end)

    "FROM " <> binds
  end

  defp gen_where(wheres) do
    exprs = Enum.map_join(wheres, " AND ", fn(where) ->
      "(#{gen_expr(where)})"
    end)

    "WHERE " <> exprs
  end

  defp gen_expr({ expr, _, [] }) do
    gen_expr(expr)
  end

  defp gen_expr({ :., _, [left, right] }) do
    "#{gen_expr(left)}.#{gen_expr(right)}"
  end

  defp gen_expr({ op, _, [expr] }) when op in [:!, :not] do
    "NOT " <> gen_expr(expr)
  end

  defp gen_expr({ op, _, [left, right] }) when op in binary_ops do
    op = Dict.fetch!(binary_ops_lookup, op)
    "#{op_to_binary(left)} #{op} #{op_to_binary(right)}"
  end

  defp gen_expr({ var, _, atom }) when is_atom(atom) do
    atom_to_binary(var)
  end

  defp gen_expr(nil) do
    "NULL"
  end

  defp gen_expr(expr) do
    to_binary(expr)
  end

  defp op_to_binary({ op, _, [_, _] } = expr) when op in binary_ops do
    "(" <> gen_expr(expr) <> ")"
  end

  defp op_to_binary(expr) do
    gen_expr(expr)
  end

  # TODO: Records (Kernel.access)
  defp select_clause({ :"{}", _, elems }) do
    Enum.map_join(elems, ", ", select_clause(&1))
  end

  defp select_clause(list) when is_list(list) do
    Enum.map_join(list, ", ", select_clause(&1))
  end

  defp select_clause(expr) do
    gen_expr(expr)
  end

  defp quotify({ x, y }) do
    { :"{}", [], [x, y] }
  end

  defp quotify(ast) do
    ast
  end
end
