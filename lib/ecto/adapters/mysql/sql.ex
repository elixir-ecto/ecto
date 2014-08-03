defmodule Ecto.Adapters.Mysql.SQL do
  @moduledoc false

  # This module handles the generation of SQL code from queries and for create,
  # update and delete. All queries have to be normalized and validated for
  # correctness before given to this module.

  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util

  unary_ops = [ -: "-", +: "+" ]

  binary_ops =
    [ ==: "=", !=: "!=", <=: "<=", >=: ">=", <:  "<", >:  ">",
      and: "AND", or: "OR",
      +:  "+", -:  "-", *:  "*",
      <>: "||", ++: "||",
      pow: "^", div: "/", rem: "%",
      date_add: "+", date_sub: "-",
      ilike: "ILIKE", like: "LIKE" ]

  functions =
    [ {{:downcase, 1}, "lower"}, {{:upcase, 1}, "upper"} ]

  @binary_ops Dict.keys(binary_ops)

  Enum.map(unary_ops, fn {op, str} ->
    defp translate_name(unquote(op), 1), do: {:unary_op, unquote(str)}
  end)

  Enum.map(binary_ops, fn {op, str} ->
    defp translate_name(unquote(op), 2), do: {:binary_op, unquote(str)}
  end)

  Enum.map(functions, fn {{fun, arity}, str} ->
    defp translate_name(unquote(fun), unquote(arity)), do: {:fun, unquote(str)}
  end)

  defp translate_name(fun, _arity), do: {:fun, Atom.to_string(fun)}

  defp quote_table(table), do: "\"#{table}\""

  defp quote_column(column), do: "\"#{column}\""

  # Generate SQL for a select statement
  def select(query) do
    # Generate SQL for every query expression type and combine to one string
    sources  = create_names(query)

    from     = from(sources)
    select   = select(query.select, query.distincts, sources)
    join     = join(query, sources)
    where    = where(query.wheres, sources)
    group_by = group_by(query.group_bys, sources)
    having   = having(query.havings, sources)
    order_by = order_by(query.order_bys, sources)
    limit    = limit(query.limit)
    offset   = offset(query.offset)
    lock     = lock(query.lock)

    [select, from, join, where, group_by, having, order_by, limit, offset, lock]
      |> Enum.filter(&(&1 != nil))
      |> List.flatten
      |> Enum.join("\n")
  end

  # Generate SQL for an insert statement
  def insert(model, returning) do
    module = model.__struct__
    table  = module.__schema__(:source)

    {fields, values} = module.__schema__(:keywords, model)
      |> Enum.filter(fn {_, val} -> val != nil end)
      |> :lists.unzip

    sql = "INSERT INTO #{quote_table(table)}"

    if fields == [] do
      sql = sql <> " DEFAULT VALUES"
    else
      sql = sql <>
        " (" <> Enum.map_join(fields, ", ", &quote_column(&1)) <> ")\n" <>
        "VALUES (" <> Enum.map_join(values, ", ", &literal(&1)) <> ")"
    end

    if !Enum.empty?(returning) do
      sql = sql <> "\nRETURNING " <> Enum.map_join(returning, ", ", &quote_column(&1))
    end

    sql
  end

  # Generate SQL for an update statement
  def update(model) do
    module   = model.__struct__
    table    = module.__schema__(:source)
    pk_field = module.__schema__(:primary_key)
    pk_value = Map.get(model, pk_field)

    zipped = module.__schema__(:keywords, model, primary_key: false)

    zipped_sql = Enum.map_join(zipped, ", ", fn {k, v} ->
      "#{quote_column(k)} = #{literal(v)}"
    end)

    "UPDATE #{quote_table(table)} SET " <> zipped_sql <> "\n" <>
    "WHERE #{quote_column(pk_field)} = #{literal(pk_value)}"
  end

  # Generate SQL for an update all statement
  def update_all(query, values) do
    names = create_names(query)
    from  = elem(names, 0)
    {table, name} = Util.source(from)

    zipped_sql = Enum.map_join(values, ", ", fn {field, expr} ->
      "#{quote_column(field)} = #{expr(expr, names)}"
    end)

    where = if query.wheres == [], do: "", else: "\n" <> where(query.wheres, names)

    "UPDATE #{quote_table(table)} AS #{name}\n" <>
    "SET " <> zipped_sql <>
    where
  end

  # Generate SQL for a delete statement
  def delete(model) do
    module   = model.__struct__
    table    = module.__schema__(:source)
    pk_field = module.__schema__(:primary_key)
    pk_value = Map.get(model, pk_field)

    "DELETE FROM #{quote_table(table)} WHERE #{quote_column(pk_field)} = #{literal(pk_value)}"
  end

  # Generate SQL for an delete all statement
  def delete_all(query) do
    names  = create_names(query)
    from   = elem(names, 0)
    {table, name} = Util.source(from)

    where = if query.wheres == [], do: "", else: "\n" <> where(query.wheres, names)
    "DELETE FROM #{quote_table(table)} AS #{name}" <> where
  end

  defp select(%QueryExpr{expr: expr}, [], sources) do
    "SELECT " <> select_clause(expr, sources)
  end

  defp select(%QueryExpr{expr: expr}, distincts, sources) do
    exprs =
      Enum.map_join(distincts, ", ", fn expr ->
        Enum.map_join(expr.expr, ", ", &expr(&1, sources))
      end)

    "SELECT DISTINCT ON (" <> exprs <> ") " <> select_clause(expr, sources)
  end

  defp from(sources) do
    {table, name} = elem(sources, 0) |> Util.source
    "FROM #{quote_table(table)} AS #{name}"
  end

  defp join(query, sources) do
    joins = Stream.with_index(query.joins)
    Enum.map(joins, fn {join, ix} ->
      source = elem(sources, ix+1)
      {table, name} = Util.source(source)

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
    exprs =
      Enum.map_join(group_bys, ", ", fn expr ->
        Enum.map_join(expr.expr, ", ", &expr(&1, sources))
      end)

    "GROUP BY " <> exprs
  end

  defp having(havings, sources) do
    boolean("HAVING", havings, sources)
  end

  defp order_by([], _sources), do: nil

  defp order_by(order_bys, sources) do
    exprs =
      Enum.map_join(order_bys, ", ", fn expr ->
        Enum.map_join(expr.expr, ", ", &order_by_expr(&1, sources))
      end)

    "ORDER BY " <> exprs
  end

  defp order_by_expr({dir, expr}, sources) do
    str = expr(expr, sources)
    case dir do
      :asc  -> str
      :desc -> str <> " DESC"
    end
  end

  defp limit(nil), do: nil
  defp limit(num), do: "LIMIT " <> Integer.to_string(num)

  defp offset(nil), do: nil
  defp offset(num), do: "OFFSET " <> Integer.to_string(num)

  defp lock(nil), do: nil
  defp lock(false), do: nil
  defp lock(true), do: "FOR UPDATE"
  defp lock(lock_clause), do: lock_clause

  defp boolean(_name, [], _sources), do: nil

  defp boolean(name, query_exprs, sources) do
    exprs = Enum.map_join(query_exprs, " AND ", fn %QueryExpr{expr: expr} ->
      "(" <> expr(expr, sources) <> ")"
    end)

    name <> " " <> exprs
  end

  defp expr({:., _, [{:&, _, [_]} = var, field]}, sources) when is_atom(field) do
    {_, name} = Util.find_source(sources, var) |> Util.source
    "#{name}.#{quote_column(field)}"
  end

  defp expr({:!, _, [expr]}, sources) do
    "NOT (" <> expr(expr, sources) <> ")"
  end

  defp expr({:&, _, [_]} = var, sources) do
    source = Util.find_source(sources, var)
    model = Util.model(source)
    fields = model.__schema__(:field_names)
    {_, name} = Util.source(source)
    Enum.map_join(fields, ", ", &"#{name}.#{quote_column(&1)}")
  end

  defp expr({:==, _, [nil, right]}, sources) do
    "#{op_to_binary(right, sources)} IS NULL"
  end

  defp expr({:==, _, [left, nil]}, sources) do
    "#{op_to_binary(left, sources)} IS NULL"
  end

  defp expr({:!=, _, [nil, right]}, sources) do
    "#{op_to_binary(right, sources)} IS NOT NULL"
  end

  defp expr({:!=, _, [left, nil]}, sources) do
    "#{op_to_binary(left, sources)} IS NOT NULL"
  end

  defp expr({:in, _, [left, first .. last]}, sources) do
    sqls = [ expr(left, sources), "BETWEEN", expr(first, sources), "AND",
             expr(last, sources) ]
    Enum.join(sqls, " ")
  end

  defp expr({:in, _, [left, {:.., _, [first, last]}]}, sources) do
    sqls = [ expr(left, sources), "BETWEEN", expr(first, sources), "AND",
             expr(last, sources) ]
    Enum.join(sqls, " ")
  end

  defp expr({:in, _, [left, right]}, sources) do
    expr(left, sources) <> " = ANY (" <> expr(right, sources) <> ")"
  end

  defp expr((_ .. _) = range, sources) do
    expr(Enum.to_list(range), sources)
  end

  defp expr({:.., _, [first, last]}, sources) do
    expr(Enum.to_list(first..last), sources)
  end

  defp expr({:/, _, [left, right]}, sources) do
    op_to_binary(left, sources) <> " / " <> op_to_binary(right, sources) <> "::numeric"
  end

  defp expr({arg, _, []}, sources) when is_tuple(arg) do
    expr(arg, sources)
  end

  defp expr({:date, _, [datetime]}, sources) do
    expr(datetime, sources) <> "::date"
  end

  defp expr({:time, _, [datetime]}, sources) do
    expr(datetime, sources) <> "::time"
  end

  defp expr({:datetime, _, [date, time]}, sources) do
    "(#{expr(date, sources)} + #{expr(time, sources)})"
  end

  defp expr({fun, _, args}, sources) when is_atom(fun) and is_list(args) do
    case translate_name(fun, length(args)) do
      {:unary_op, op} ->
        arg = expr(List.first(args), sources)
        op <> arg
      {:binary_op, op} ->
        [left, right] = args
        op_to_binary(left, sources) <> " #{op} " <> op_to_binary(right, sources)
      {:fun, "localtimestamp"} ->
        "localtimestamp"
      {:fun, fun} ->
        "#{fun}(" <> Enum.map_join(args, ", ", &expr(&1, sources)) <> ")"
    end
  end

  defp expr(%Ecto.Tagged{value: list, type: {:array, inner}}, sources) do
    sql = "ARRAY[" <> Enum.map_join(list, ", ", &expr(&1, sources)) <> "]"
    if list == [], do: sql = sql <> "::#{type(inner)}[]"
    sql
  end

  defp expr(literal, _sources), do: literal(literal)

  defp literal(nil), do: "NULL"

  defp literal(true), do: "TRUE"

  defp literal(false), do: "FALSE"

  defp literal(%Ecto.DateTime{year: year, month: month, day: day, hour: hour, min: min, sec: sec}) do
    "timestamp '#{year}-#{month}-#{day} #{hour}:#{min}:#{sec}'"
  end

  defp literal(%Ecto.Date{year: year, month: month, day: day}) do
    "date '#{year}-#{month}-#{day}'"
  end

  defp literal(%Ecto.Time{hour: hour, min: min, sec: sec}) do
    "time '#{hour}:#{min}:#{sec}'"
  end

  defp literal(%Ecto.Interval{year: year, month: month, day: day, hour: hour, min: min, sec: sec}) do
    "interval 'P#{year}-#{month}-#{day}T#{hour}:#{min}:#{sec}'"
  end

  defp literal(%Ecto.Tagged{value: binary, type: :binary}) do
    hex = for <<h :: unsigned-4, l :: unsigned-4 <- binary>> do
      Integer.to_string(h, 16) <> Integer.to_string(l, 16)
    end
    "'\\x#{hex}'::bytea"
  end

  defp literal(%Ecto.Tagged{value: list, type: {:array, inner}}) do
    "ARRAY[" <> Enum.map_join(list, ", ", &literal(&1)) <> "]::#{type(inner)}[]"
  end

  defp literal(literal) when is_binary(literal) do
    "'#{escape_string(literal)}'"
  end

  defp literal(literal) when is_integer(literal) do
    to_string(literal)
  end

  defp literal(literal) when is_float(literal) do
    to_string(literal) <> "::float"
  end

  defp literal(%Decimal{} = num) do
    str = Decimal.to_string(num, :normal)
    if :binary.match(str, ".") == :nomatch, do: str = str <> ".0"
    str
  end

  defp op_to_binary({op, _, [_, _]} = expr, sources) when op in @binary_ops do
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
  defp flatten_select({atom, _} = record) when is_atom(atom) do
    [record]
  end

  defp flatten_select({left, right}) do
    flatten_select({:{}, [], [left, right]})
  end

  defp flatten_select({:{}, _, elems}) do
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

  # Must be kept up to date with Util.types and Util.poly_types
  defp type(:boolean),  do: "boolean"
  defp type(:string),   do: "text"
  defp type(:integer),  do: "integer"
  defp type(:float),    do: "float"
  defp type(:binary),   do: "bytea"
  defp type(:datetime), do: "timestamp without time zone"
  defp type(:interval), do: "interval"

  defp type({:array, inner}), do: type(inner) <> "[]"

  defp create_names(query) do
    sources = query.sources |> Tuple.to_list
    Enum.reduce(sources, [], fn {table, model}, names ->
      name = unique_name(names, String.first(table), 0)
      [{{table, name}, model}|names]
    end) |> Enum.reverse |> List.to_tuple
  end

  # Brute force find unique name
  defp unique_name(names, name, counter) do
    counted_name = name <> Integer.to_string(counter)
    if Enum.any?(names, fn {{_, n}, _} -> n == counted_name end) do
      unique_name(names, name, counter+1)
    else
      counted_name
    end
  end
end
