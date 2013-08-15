defmodule Ecto.Adapters.Postgres.SQL do
  @moduledoc false

  # This module handles the generation of SQL code from queries and for create,
  # update and delete. All queries has to be normalized and validated for
  # correctness before given to this module.

  require Ecto.Query
  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util

  unary_ops = [ -: "-", +: "+" ]

  binary_ops =
    [ ==: "=", !=: "!=", <=: "<=", >=: ">=", <:  "<", >:  ">",
      and: "AND", or: "OR",
      +:  "+", -:  "-", *:  "*",
      <>: "||", ++: "||",
      pow: "^", div: "/", rem: "%" ]

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
    entities = create_names(query)
    { from, used_names } = from(query.from, entities)
    select   = select(query.select, entities)
    join     = join(query.joins, entities, used_names)
    where    = where(query.wheres, entities)
    group_by = group_by(query.group_bys, entities)
    having   = having(query.havings, entities)
    order_by = order_by(query.order_bys, entities)
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
    table       = module.__ecto__(:dataset)
    primary_key = module.__ecto__(:primary_key)

    zipped = module.__ecto__(:entity_kw, entity)

    # Don't insert primary key
    if primary_key do
      [_|zipped] = zipped
    end

    [ fields, values ] = List.unzip(zipped)

    "INSERT INTO #{table} (" <> Enum.join(fields, ", ") <> ")\n" <>
    "VALUES (" <> Enum.map_join(values, ", ", &literal(&1)) <> ")" <>
    if primary_key, do: "\nRETURNING #{primary_key}", else: ""
  end

  # Generate SQL for an update statement
  def update(entity) do
    module      = elem(entity, 0)
    table       = module.__ecto__(:dataset)

    zipped = module.__ecto__(:entity_kw, entity)
    [{ pk_field, pk_value }|zipped] = zipped

    zipped_sql = Enum.map_join(zipped, ", ", fn({k, v}) ->
      "#{k} = #{literal(v)}"
    end)

    "UPDATE #{table} SET " <> zipped_sql <> "\n" <>
    "WHERE #{pk_field} = #{literal(pk_value)}"
  end

  # Generate SQL for an update all statement
  def update_all(module, values) when is_atom(module) do
    update_all(Query[from: module], values)
  end

  def update_all(Query[] = query, values) do
    module = query.from
    names  = create_names(query)
    entity = elem(names, 0)
    name   = elem(entity, 1)
    table  = module.__ecto__(:dataset)

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
    module      = elem(entity, 0)
    table       = module.__ecto__(:dataset)
    primary_key = module.__ecto__(:primary_key)
    pk_value    = elem(entity, 1)

    "DELETE FROM #{table} WHERE #{primary_key} = #{literal(pk_value)}"
  end

  # Generate SQL for an delete all statement
  def delete_all(module) when is_atom(module) do
    delete_all(Query[from: module])
  end

  def delete_all(Query[] = query) do
    module = query.from
    names  = create_names(query)
    entity = elem(names, 0)
    name   = elem(entity, 1)
    table  = module.__ecto__(:dataset)

    where = if query.wheres == [], do: "", else: "\n" <> where(query.wheres, names)

    "DELETE FROM #{table} AS #{name}" <> where
  end

  defp select(QueryExpr[expr: expr], entities) do
    "SELECT " <> select_clause(expr, entities)
  end

  defp from(from, entities) do
    name = tuple_to_list(entities) |> Keyword.fetch!(from)
    { "FROM #{from.__ecto__(:dataset)} AS #{name}", [name] }
  end

  defp join(joins, entities, used_names) do
    # We need to make sure that we get a unique name for each entity since
    # the same entity can be referenced multiple times in joins
    entities_list = tuple_to_list(entities)
    Enum.map_reduce(joins, used_names, fn(QueryExpr[expr: expr], names) ->
      { join, on } = expr
      { entity, name } = Enum.find(entities_list, fn({ entity, name }) ->
        entity == join and not name in names
      end)

      on_sql = expr(on, entities)

      { "JOIN #{entity.__ecto__(:dataset)} AS #{name} ON " <> on_sql, [name|names] }
    end) |> elem(0)
  end

  defp where(wheres, entities) do
    boolean("WHERE", wheres, entities)
  end

  defp group_by([], _entities), do: nil

  defp group_by(group_bys, entities) do
    exprs = Enum.map_join(group_bys, ", ", fn(expr) ->
      Enum.map_join(expr.expr, ", ", fn({ var, field }) ->
        { _entity, name } = Util.find_entity(entities, var)
        "#{name}.#{field}"
      end)
    end)

    "GROUP BY " <> exprs
  end

  defp having(havings, entities) do
    boolean("HAVING", havings, entities)
  end

  defp order_by([], _vars), do: nil

  defp order_by(order_bys, entities) do
    exprs = Enum.map_join(order_bys, ", ", fn(expr) ->
      Enum.map_join(expr.expr, ", ", &order_by_expr(&1, entities))
    end)

    "ORDER BY " <> exprs
  end

  defp order_by_expr({ dir, var, field }, vars) do
    { _entity, name } = Util.find_entity(vars, var)
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

  defp boolean(_name, [], _vars), do: nil

  defp boolean(name, query_exprs, entities) do
    exprs = Enum.map_join(query_exprs, " AND ", fn(QueryExpr[expr: expr]) ->
      "(" <> expr(expr, entities) <> ")"
    end)

    name <> " " <> exprs
  end

  defp expr({ :., _, [{ :&, _, [_] } = var, field] }, vars) when is_atom(field) do
    { _entity, name } = Util.find_entity(vars, var)
    "#{name}.#{field}"
  end

  defp expr({ :!, _, [expr] }, vars) do
    "NOT (" <> expr(expr, vars) <> ")"
  end

  # Expression builders make sure that we only find undotted vars at the top level
  defp expr({ :&, _, [_] } = var, vars) do
    { entity, name } = Util.find_entity(vars, var)
    fields = entity.__ecto__(:field_names)
    Enum.map_join(fields, ", ", &"#{name}.#{&1}")
  end

  defp expr({ :==, _, [nil, right] }, vars) do
    "#{op_to_binary(right, vars)} IS NULL"
  end

  defp expr({ :==, _, [left, nil] }, vars) do
    "#{op_to_binary(left, vars)} IS NULL"
  end

  defp expr({ :!=, _, [nil, right] }, vars) do
    "#{op_to_binary(right, vars)} IS NOT NULL"
  end

  defp expr({ :!=, _, [left, nil] }, vars) do
    "#{op_to_binary(left, vars)} IS NOT NULL"
  end

  defp expr({ :in, _, [left, Range[first: first, last: last]] }, vars) do
    expr(left, vars) <> " BETWEEN " <> expr(first, vars) <> " AND " <> expr(last, vars)
  end

  defp expr({ :in, _, [left, { :.., _, [first, last] }] }, vars) do
    expr(left, vars) <> " BETWEEN " <> expr(first, vars) <> " AND " <> expr(last, vars)
  end

  defp expr({ :in, _, [left, right] }, vars) do
    expr(left, vars) <> " = ANY (" <> expr(right, vars) <> ")"
  end

  defp expr(Range[] = range, vars) do
    expr(Enum.to_list(range), vars)
  end

  defp expr({ :.., _, [first, last] }, vars) do
    expr(Enum.to_list(first..last), vars)
  end

  defp expr({ :/, _, [left, right] }, vars) do
    op_to_binary(left, vars) <> " / " <> op_to_binary(right, vars) <> "::float"
  end

  defp expr({ arg, _, [] }, vars) when is_tuple(arg) do
    expr(arg, vars)
  end

  defp expr({ fun, _, args }, vars) when is_atom(fun) and is_list(args) do
    case translate_name(fun, length(args)) do
      { :unary_op, op } ->
        arg = expr(Enum.first(args), vars)
        op <> arg
      { :binary_op, op } ->
        [left, right] = args
        op_to_binary(left, vars) <> " #{op} " <> op_to_binary(right, vars)
      { :fun, fun } ->
        "#{fun}(" <> Enum.map_join(args, ", ", &expr(&1, vars)) <> ")"
    end
  end

  defp expr(list, vars) when is_list(list) do
    "ARRAY[" <> Enum.map_join(list, ", ", &expr(&1, vars)) <> "]"
  end

  defp expr(literal, _vars), do: literal(literal)

  defp literal(nil), do: "NULL"

  defp literal(true), do: "TRUE"

  defp literal(false), do: "FALSE"

  defp literal(literal) when is_binary(literal) do
    "'#{escape_string(literal)}'"
  end

  defp literal(literal) when is_number(literal) do
    to_binary(literal)
  end

  defp op_to_binary({ op, _, [_, _] } = expr, vars) when op in @binary_ops do
    "(" <> expr(expr, vars) <> ")"
  end

  defp op_to_binary(expr, vars) do
    expr(expr, vars)
  end

  # TODO: Records (Kernel.access)
  defp select_clause({ :{}, _, elems }, vars) do
    Enum.map_join(elems, ", ", &select_clause(&1, vars))
  end

  defp select_clause({ x, y }, vars) do
    select_clause({ :{}, [], [x, y] }, vars)
  end

  defp select_clause(list, vars) when is_list(list) do
    Enum.map_join(list, ", ", &select_clause(&1, vars))
  end

  defp select_clause(expr, vars) do
    expr(expr, vars)
  end

  defp escape_string(value) when is_binary(value) do
    value
      |> :binary.replace("\\", "\\\\", [:global])
      |> :binary.replace("'", "''", [:global])
  end

  defp create_names(query) do
    entities = query.entities |> tuple_to_list
    Enum.reduce(entities, [], fn(entity, names) ->
      table = entity.__ecto__(:dataset) |> String.first
      name = unique_name(names, table, 0)
      [{ entity, name }|names]
    end) |> Enum.reverse |> list_to_tuple
  end

  # Brute force find unique name
  defp unique_name(names, name, counter) do
    cnt_name = name <> integer_to_binary(counter)
    if Enum.any?(names, fn({ _, n }) -> n == cnt_name end) do
      unique_name(names, name, counter+1)
    else
      cnt_name
    end
  end
end
