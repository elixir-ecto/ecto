defmodule Ecto.Adapters.Postgres.SQL do
  @moduledoc false

  # This module handles the generation of SQL code from queries and for create,
  # update and delete. All queries has to be normalized and validated for
  # correctness before given to this module.

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr
  alias Ecto.Query.Util
  alias Ecto.Query.Normalizer
  alias Ecto.Query.NameResolution

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

  defp translate_name(fun, _arity), do: { :fun, atom_to_binary(fun) }

  # Generate SQL for a select statement
  def select(Query[] = query) do
    # Generate SQL for every query expression type and combine to one string
    sources = NameResolution.create_names(query)
    { from, used_names } = from(query.from, sources)

    select   = select(query.select, sources)
    join     = join(query, sources, used_names)
    where    = where(query.wheres, sources)
    group_by = group_by(query.group_bys, sources)
    having   = having(query.havings, sources)
    order_by = order_by(query.order_bys, sources)
    limit    = limit(query.limit)
    offset   = offset(query.offset)

    [select, from, join, where, group_by, having, order_by, limit, offset]
      |> Enum.filter(&(&1 != nil))
      |> List.flatten
      |> Enum.join("\n")
  end

  # Generate SQL for an insert statement
  def insert(entity) do
    module      = elem(entity, 0)
    table       = entity.model.__model__(:source)
    primary_key = module.__entity__(:primary_key)
    pk_value    = entity.primary_key

    zipped = module.__entity__(:entity_kw, entity, primary_key: !!pk_value)

    [ fields, values ] = List.unzip(zipped)

    "INSERT INTO #{table} (" <> Enum.join(fields, ", ") <> ")\n" <>
    "VALUES (" <> Enum.map_join(values, ", ", &literal(&1)) <> ")" <>
    if primary_key && !pk_value, do: "\nRETURNING #{primary_key}", else: ""
  end

  # Generate SQL for an update statement
  def update(entity) do
    module   = elem(entity, 0)
    table    = entity.model.__model__(:source)
    pk_field = module.__entity__(:primary_key)
    pk_value = entity.primary_key

    zipped = module.__entity__(:entity_kw, entity, primary_key: false)

    zipped_sql = Enum.map_join(zipped, ", ", fn({k, v}) ->
      "#{k} = #{literal(v)}"
    end)

    "UPDATE #{table} SET " <> zipped_sql <> "\n" <>
    "WHERE #{pk_field} = #{literal(pk_value)}"
  end

  # Generate SQL for an update all statement
  def update_all(Query[] = query, values) do
    names  = NameResolution.create_names(query)
    from = elem(names, 0)
    { table, name } = Util.source(from)

    zipped_sql = Enum.map_join(values, ", ", fn({field, expr}) ->
      "#{field} = #{expr(expr, names)}"
    end)

    where = if query.wheres == [], do: "", else: "\n" <> where(query.wheres, names)

    "UPDATE #{table} AS #{name}\n" <>
    "SET " <> zipped_sql <>
    where
  end

  # Generate SQL for a delete statement
  def delete(entity) do
    module   = elem(entity, 0)
    table    = entity.model.__model__(:source)
    pk_field = module.__entity__(:primary_key)
    pk_value = entity.primary_key

    "DELETE FROM #{table} WHERE #{pk_field} = #{literal(pk_value)}"
  end

  # Generate SQL for an delete all statement
  def delete_all(Query[] = query) do
    names  = NameResolution.create_names(query)
    from   = elem(names, 0)
    { table, name } = Util.source(from)

    where = if query.wheres == [], do: "", else: "\n" <> where(query.wheres, names)
    "DELETE FROM #{table} AS #{name}" <> where
  end

  defp select(expr, sources) do
    QueryExpr[expr: expr] = Normalizer.normalize_select(expr)
    "SELECT " <> select_clause(expr, sources)
  end

  defp from(from, sources) do
    from_model = Util.model(from)
    source = tuple_to_list(sources) |> Enum.find(&(from_model == Util.model(&1)))
    { table, name } = Util.source(source)
    { "FROM #{table} AS #{name}", [name] }
  end

  defp join(Query[] = query, sources, used_names) do
    # We need to make sure that we get a unique name for each entity since
    # the same entity can be referenced multiple times in joins

    sources_list = tuple_to_list(sources)
    Enum.map_reduce(query.joins, used_names, fn(join, names) ->
      join = JoinExpr[] = Normalizer.normalize_join(join, query)

      source = Enum.find(sources_list, fn({ { source, name }, _, model }) ->
        ((source == join.source) or (model == join.source)) and not name in names
      end)

      { table, name } = Util.source(source)
      on_sql = expr(join.on.expr, sources)
      qual = join_qual(join.qual)

      { "#{qual} JOIN #{table} AS #{name} ON " <> on_sql, [name|names] }
    end) |> elem(0)
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
    exprs = Enum.map_join(group_bys, ", ", fn(expr) ->
      Enum.map_join(expr.expr, ", ", fn({ var, field }) ->
        { _, name } = Util.find_source(sources, var) |> Util.source
        "#{name}.#{field}"
      end)
    end)

    "GROUP BY " <> exprs
  end

  defp having(havings, sources) do
    boolean("HAVING", havings, sources)
  end

  defp order_by([], _sources), do: nil

  defp order_by(order_bys, sources) do
    exprs = Enum.map_join(order_bys, ", ", fn(expr) ->
      Enum.map_join(expr.expr, ", ", &order_by_expr(&1, sources))
    end)

    "ORDER BY " <> exprs
  end

  defp order_by_expr({ dir, var, field }, sources) do
    { _, name } = Util.find_source(sources, var) |> Util.source
    str = "#{name}.#{field}"
    case dir do
      nil   -> str
      :asc  -> str <> " ASC"
      :desc -> str <> " DESC"
    end
  end

  defp limit(nil), do: nil
  defp limit(num), do: "LIMIT " <> integer_to_binary(num)

  defp offset(nil), do: nil
  defp offset(num), do: "OFFSET " <> integer_to_binary(num)

  defp boolean(_name, [], _sources), do: nil

  defp boolean(name, query_exprs, sources) do
    exprs = Enum.map_join(query_exprs, " AND ", fn(QueryExpr[expr: expr]) ->
      "(" <> expr(expr, sources) <> ")"
    end)

    name <> " " <> exprs
  end

  defp expr({ :., _, [{ :&, _, [_] } = var, field] }, sources) when is_atom(field) do
    { _, name } = Util.find_source(sources, var) |> Util.source
    "#{name}.#{field}"
  end

  defp expr({ :!, _, [expr] }, sources) do
    "NOT (" <> expr(expr, sources) <> ")"
  end

  defp expr({ :&, _, [_] } = var, sources) do
    source = Util.find_source(sources, var)
    entity = Util.entity(source)
    fields = entity.__entity__(:field_names)
    { _, name } = Util.source(source)
    Enum.map_join(fields, ", ", &"#{name}.#{&1}")
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

  defp expr({ :in, _, [left, Range[first: first, last: last]] }, sources) do
    sqls = [ expr(left, sources), "BETWEEN", expr(first, sources), "AND",
             expr(last, sources) ]
    Enum.join(sqls, " ")
  end

  defp expr({ :in, _, [left, { :.., _, [first, last] }] }, sources) do
    sqls = [ expr(left, sources), "BETWEEN", expr(first, sources), "AND",
             expr(last, sources) ]
    Enum.join(sqls, " ")
  end

  defp expr({ :in, _, [left, right] }, sources) do
    expr(left, sources) <> " = ANY (" <> expr(right, sources) <> ")"
  end

  defp expr(Range[] = range, sources) do
    expr(Enum.to_list(range), sources)
  end

  defp expr({ :.., _, [first, last] }, sources) do
    expr(Enum.to_list(first..last), sources)
  end

  defp expr({ :/, _, [left, right] }, sources) do
    op_to_binary(left, sources) <> " / " <> op_to_binary(right, sources) <> "::float"
  end

  defp expr({ arg, _, [] }, sources) when is_tuple(arg) do
    expr(arg, sources)
  end

  defp expr({ fun, _, args }, sources) when is_atom(fun) and is_list(args) do
    case translate_name(fun, length(args)) do
      { :unary_op, op } ->
        arg = expr(Enum.first(args), sources)
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
    "ARRAY[" <> Enum.map_join(list, ", ", &expr(&1, sources)) <> "]"
  end

  defp expr(literal, _sources), do: literal(literal)

  defp literal(nil), do: "NULL"

  defp literal(true), do: "TRUE"

  defp literal(false), do: "FALSE"

  defp literal(Ecto.DateTime[] = dt) do
    "timestamp '#{dt.year}-#{dt.month}-#{dt.day} #{dt.hour}:#{dt.min}:#{dt.sec}'"
  end

  defp literal(Ecto.Interval[] = i) do
    "interval 'P#{i.year}-#{i.month}-#{i.day}T#{i.hour}:#{i.min}:#{i.sec}'"
  end

  defp literal(Ecto.Binary[value: binary]) do
    hex = lc << h :: [unsigned, 4], l :: [unsigned, 4] >> inbits binary do
      fixed_integer_to_binary(h, 16) <> fixed_integer_to_binary(l, 16)
    end
    "'\\x#{hex}'::bytea"
  end

  defp literal(literal) when is_binary(literal) do
    "'#{escape_string(literal)}'::text"
  end

  defp literal(literal) when is_number(literal) do
    to_string(literal)
  end

  defp op_to_binary({ op, _, [_, _] } = expr, sources) when op in @binary_ops do
    "(" <> expr(expr, sources) <> ")"
  end

  defp op_to_binary(expr, sources) do
    expr(expr, sources)
  end

  # TODO: Records (Kernel.access)
  defp select_clause({ :{}, _, elems }, sources) do
    Enum.map_join(elems, ", ", &select_clause(&1, sources))
  end

  defp select_clause(list, sources) when is_list(list) do
    Enum.map_join(list, ", ", &select_clause(&1, sources))
  end

  defp select_clause(expr, sources) do
    expr(expr, sources)
  end

  defp escape_string(value) when is_binary(value) do
    :binary.replace(value, "'", "''", [:global])
  end

  # This is fixed in R16B02, we can remove this fix when we stop supporting R16B01
  defp fixed_integer_to_binary(0, _), do: "0"
  defp fixed_integer_to_binary(value, base), do: integer_to_binary(value, base)
end
