defmodule Ecto.Adapters.Mysql.SQL do
  @moduledoc false

  # This module handles the generation of SQL code from queries and for create,
  # update and delete. All queries has to be normalized and validated for
  # correctness before given to this module.

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr
  alias Ecto.Query.Util

  unary_ops = [ -: "-", +: "+" ]

  binary_ops =
    [ ==: "=", !=: "!=", <=: "<=", >=: ">=", <:  "<", >:  ">",
      and: "AND", or: "OR",
      +:  "+", -:  "-", *:  "*",
      <>: "||", ++: "||",
      div: "/", rem: "%",
      date_add: "+", date_sub: "-",
      ilike: "ILIKE", like: "LIKE" ]

  functions =
    [ { { :downcase, 1 }, "lower" }, { { :upcase, 1 }, "upper" } ]

  @binary_ops Dict.keys(binary_ops)

  Enum.map(unary_ops, fn { op, str } ->
    defp translate_name(unquote(op), 1), do: { :unary_op, unquote(str) }
  end)

  Enum.map(binary_ops, fn { op, str } ->
    defp translate_name(unquote(op), 2), do: { :binary_op, unquote(str) }
  end)

  Enum.map(functions, fn { { fun, arity }, str } ->
    defp translate_name(unquote(fun), unquote(arity)), do: { :fun, unquote(str) }
  end)

  defp quote_table(table), do: "`#{table}`"

  defp quote_column(column), do: "`#{column}`"

  defp translate_name(fun, _arity), do: { :fun, atom_to_binary(fun) }

  # Generate SQL for a select statement
  def select(Query[] = query) do
    # Generate SQL for every query expression type and combine to one string
    sources  = create_names(query)

    from     = from(sources)
    select   = select(query.select, sources)
    join     = join(query, sources)
    where    = where(query.wheres, sources)
    group_by = group_by(query.group_bys, sources)
    having   = having(query.havings, sources)
    order_by = order_by(query.order_bys, sources)
    limit    = limit(query.limit)
    offset   = offset(query.offset)

    [select, from, join, where, group_by, having, order_by, limit, offset]
      |> Enum.filter(&(&1 != nil))
      |> List.flatten
      |> Enum.join(" ")
  end

  # Generate SQL for an insert statement
  def insert(entity) do
    module = elem(entity, 0)
    table  = entity.model.__model__(:source)

    { fields, values } = module.__entity__(:keywords, entity)
      |> Enum.filter(fn { _, val } -> val != nil end)
      |> :lists.unzip

    sql = "INSERT INTO #{quote_table(table)}"

    if fields == [] do
      sql = sql <> " () VALUES ()"
    else
      sql = sql <>
        " (" <> Enum.map_join(fields, ", ", &quote_column(&1)) <> ") " <>
        "VALUES (" <> Enum.map_join(values, ", ", &literal(&1)) <> ")"
    end

    sql
  end

  # Generate SQL for an update statement
  def update(entity) do
    module   = elem(entity, 0)
    table    = entity.model.__model__(:source)
    pk_field = module.__entity__(:primary_key)
    pk_value = entity.primary_key

    zipped = module.__entity__(:keywords, entity, primary_key: false)

    zipped_sql = Enum.map_join(zipped, ", ", fn { k, v } ->
      "#{quote_column(k)} = #{literal(v)}"
    end)

    "UPDATE #{quote_table(table)} SET " <> zipped_sql <> " " <>
    "WHERE #{quote_column(pk_field)} = #{literal(pk_value)}"
  end

  # Generate SQL for an update all statement
  def update_all(Query[] = query, values) do
    names = create_names(query)
    from  = elem(names, 0)
    { table, name } = Util.source(from)

    zipped_sql = Enum.map_join(values, ", ", fn { field, expr } ->
      "#{quote_column(field)} = #{expr(expr, names)}"
    end)

    where = if query.wheres == [], do: "", else: " " <> where(query.wheres, names)

    "UPDATE #{quote_table(table)} AS #{name} " <>
    "SET " <> zipped_sql <>
    where
  end

  # Generate SQL for a delete statement
  def delete(entity) do
    module   = elem(entity, 0)
    table    = entity.model.__model__(:source)
    pk_field = module.__entity__(:primary_key)
    pk_value = entity.primary_key

    "DELETE FROM #{quote_table(table)} WHERE #{quote_column(pk_field)} = #{literal(pk_value)}"
  end

  # Generate SQL for an delete all statement
  def delete_all(Query[] = query) do
    names  = create_names(query)
    from   = elem(names, 0)
    { table, name } = Util.source(from)

    where = if query.wheres == [], do: "", else: " " <> where(query.wheres, names)
    "DELETE FROM #{name} USING #{quote_table(table)} AS #{name}" <> where
  end

  defp select(QueryExpr[expr: expr], sources) do
    "SELECT " <> select_clause(expr, sources)
  end

  defp from(sources) do
    { table, name } = elem(sources, 0) |> Util.source
    "FROM #{quote_table(table)} AS #{name}"
  end

  defp join(Query[] = query, sources) do
    joins = Stream.with_index(query.joins)
    Enum.map(joins, fn { JoinExpr[] = join, ix } ->
      source = elem(sources, ix+1)
      { table, name } = Util.source(source)

      on_sql = expr(join.on.expr, sources)
      qual = join_qual(join.qual)
      "#{qual} JOIN #{quote_table(table)} AS #{name} ON " <> on_sql
    end)
  end

  defp join_qual(:inner), do: "INNER"
  defp join_qual(:left), do: "LEFT OUTER"
  defp join_qual(:right), do: "RIGHT OUTER"
  defp join_qual(:full), do: "FULL OUTER"

  defp where(wheres, sources) do
    boolean("WHERE", wheres, sources)
  end

  defp group_by([], _sources), do: nil

  defp group_by(group_bys, sources) do
    exprs = Enum.map_join(group_bys, ", ", fn expr ->
      Enum.map_join(expr.expr, ", ", fn { var, field } ->
        { _, name } = Util.find_source(sources, var) |> Util.source
        "#{quote_table(name)}.#{quote_column(field)}"
      end)
    end)

    "GROUP BY " <> exprs
  end

  defp having(havings, sources) do
    boolean("HAVING", havings, sources)
  end

  defp order_by([], _sources), do: nil

  defp order_by(order_bys, sources) do
    exprs = Enum.map_join(order_bys, ", ", fn expr ->
      Enum.map_join(expr.expr, ", ", &order_by_expr(&1, sources))
    end)

    "ORDER BY " <> exprs
  end

  defp order_by_expr({ dir, var, field }, sources) do
    { _, name } = Util.find_source(sources, var) |> Util.source
    str = "#{quote_table(name)}.#{quote_column(field)}"
    case dir do
      :asc  -> str
      :desc -> str <> " DESC"
    end
  end

  defp limit(nil), do: nil
  defp limit(num), do: "LIMIT " <> integer_to_binary(num)

  defp offset(nil), do: nil
  defp offset(num), do: "OFFSET " <> integer_to_binary(num)

  defp boolean(_name, [], _sources), do: nil

  defp boolean(name, query_exprs, sources) do
    exprs = Enum.map_join(query_exprs, " AND ", fn QueryExpr[expr: expr] ->
      "(" <> expr(expr, sources) <> ")"
    end)

    name <> " " <> exprs
  end

  defp expr({ :., _, [{ :&, _, [_] } = var, field] }, sources) when is_atom(field) do
    { _, name } = Util.find_source(sources, var) |> Util.source
    "#{quote_table(name)}.#{quote_column(field)}"
  end

  defp expr({ :!, _, [expr] }, sources) do
    "NOT (" <> expr(expr, sources) <> ")"
  end

  defp expr({ :&, _, [_] } = var, sources) do
    source = Util.find_source(sources, var)
    entity = Util.entity(source)
    fields = entity.__entity__(:field_names)
    { _, name } = Util.source(source)
    Enum.map_join(fields, ", ", &"#{name}.#{quote_column(&1)}")
  end

  defp expr({ :==, _, [nil, right] }, sources) do
    "#{op_to_binary(right, sources)} IS NULL"
  end

  defp expr({ :==, _, [left, nil] }, sources) do
    "#{op_to_binary(left, sources)} IS NULL"
  end

  defp expr({ :!=, _, [nil, right] }, sources) do
    "#{op_to_binary(right, sources)} IS NOT NULL"
  end

  defp expr({ :!=, _, [left, nil] }, sources) do
    "#{op_to_binary(left, sources)} IS NOT NULL"
  end

  defp expr({ :in, _, [left, { :.., _, [first, last] }] }, sources) do
    sqls = [ expr(left, sources), "BETWEEN", expr(first, sources), "AND",
             expr(last, sources) ]
    Enum.join(sqls, " ")
  end

  defp expr({ :in, _, [left, right] }, sources) do
    expr(left, sources) <> " IN " <> expr(right, sources)
  end

  defp expr((_ .. _) = range, sources) do
    expr(Enum.to_list(range), sources)
  end

  defp expr({ :.., _, [first, last] }, sources) do
    expr(Enum.to_list(first..last), sources)
  end

  defp expr({ :/, _, [left, right] }, sources) do
    op_to_binary(left, sources) <> " / " <> op_to_binary(right, sources)
  end

  defp expr({ arg, _, [] }, sources) when is_tuple(arg) do
    expr(arg, sources)
  end

  defp expr({ fun, _, args }, sources) when is_atom(fun) and is_list(args) do
    case translate_name(fun, length(args)) do
      { :unary_op, op } ->
        arg = expr(List.first(args), sources)
        op <> arg
      { :binary_op, op } ->
        [left, right] = args
        op_to_binary(left, sources) <> " #{op} " <> op_to_binary(right, sources)
      { :fun, "localtimestamp" } ->
        "localtimestamp"
      { :fun, fun } ->
        "#{fun}(" <> Enum.map_join(args, ", ", &expr(&1, sources)) <> ")"
    end
  end

  defp expr(list, sources) when is_list(list) do
    "(" <> Enum.map_join(list, ", ", &expr(&1, sources)) <> ")"
  end

  defp expr(literal, _sources), do: literal(literal)

  defp literal(nil), do: "NULL"

  defp literal(true), do: "TRUE"

  defp literal(false), do: "FALSE"

  defp literal(Ecto.DateTime[] = dt) do
    "timestamp '#{dt.year}-#{dt.month}-#{dt.day} #{dt.hour}:#{dt.min}:#{dt.sec}'"
  end

  defp literal(Ecto.Binary[value: binary]) do
    hex = lc << h :: [unsigned, 4], l :: [unsigned, 4] >> inbits binary do
      fixed_integer_to_binary(h, 16) <> fixed_integer_to_binary(l, 16)
    end
    "X'#{hex}'"
  end

  defp literal(Ecto.Array[value: list]) do
    "(" <> Enum.map_join(list, ", ", &literal(&1)) <> ")"
  end

  defp literal(literal) when is_binary(literal) do
    "'#{escape_string(literal)}'"
  end

  defp literal(literal) when is_number(literal) do
    to_string(literal)
  end

  defp literal(literal) when is_list(literal) do
    "(" <> Enum.map_join(literal, ", ", &literal(&1)) <> ")"
  end

  defp op_to_binary({ op, _, [_, _] } = expr, sources) when op in @binary_ops do
    "(" <> expr(expr, sources) <> ")"
  end

  defp op_to_binary(expr, sources) do
    expr(expr, sources)
  end

  defp select_clause(expr, sources) do
    flatten_select(expr) |> Enum.map_join(", ", &expr(&1, sources))
  end

  # TODO: Records (Kernel.access)

  # Some two-tuples may be records (ex. Ecto.Binary[]), so check for records
  # explicitly. We can do this because we don't allow atoms in queries.
  defp flatten_select({ atom, _ } = record) when is_atom(atom) do
    [record]
  end

  defp flatten_select({ left, right }) do
    flatten_select({ :{}, [], [left, right] })
  end

  defp flatten_select({ :{}, _, elems }) do
    Enum.flat_map(elems, &flatten_select/1)
  end

  defp flatten_select(list) when is_list(list) do
    Enum.flat_map(list, &flatten_select/1)
  end

  defp flatten_select(expr) do
    [expr]
  end

  defp escape_string(value) when is_binary(value) do
    :binary.replace(value, "'", "''", [:global])
  end

  defp create_names(query) do
    sources = query.sources |> tuple_to_list
    Enum.reduce(sources, [], fn({ table, entity, model }, names) ->
      name = unique_name(names, String.first(table), 0)
      [{ { table, name }, entity, model }|names]
    end) |> Enum.reverse |> list_to_tuple
  end

  # Brute force find unique name
  defp unique_name(names, name, counter) do
    counted_name = name <> integer_to_binary(counter)
    if Enum.any?(names, fn { { _, n }, _, _ } -> n == counted_name end) do
      unique_name(names, name, counter+1)
    else
      counted_name
    end
  end

  # This is fixed in R16B02, we can remove this fix when we stop supporting R16B01
  defp fixed_integer_to_binary(0, _), do: "0"
  defp fixed_integer_to_binary(value, base), do: integer_to_binary(value, base)
end
