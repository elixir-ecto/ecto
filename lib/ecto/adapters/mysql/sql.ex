defmodule Ecto.Adapters.Mysql.SQL do
  @moduledoc false

  # This module handles the generation of SQL code from queries and for create,
  # update and delete. All queries has to be normalized and validated for
  # correctness before given to this module.

  require Ecto.Query
  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr
  alias Ecto.Query.Util
  alias Ecto.Query.Normalizer
  alias Ecto.Query.NameResolution

  binary_ops =
    [ ==: "=", !=: "!=", <=: "<=", >=: ">=", <:  "<", >:  ">",
      and: "AND", or: "OR",
      +:  "+", -:  "-", *:  "*",
      <>: "||", ++: "||", /: "/", rem: "%" ]

  functions =
    [ random: "RAND", round: "ROUND", pow: "POW" ]

  @binary_ops Dict.keys(binary_ops)

  def select(query) do
    models = NameResolution.create_names(query)
    { from, used_names } = from(query.from, models)

    select   = select(query.select, models)
    join     = join(query, models, used_names)
    where    = where(query.wheres, models)
    group_by = group_by(query.group_bys, models)
    order_by = order_by(query.order_bys, models)
    limit    = limit(query.limit)
    offset   = offset(query.offset)

    [select, from, join, where, group_by, order_by, limit, offset]
      |> Enum.filter(&(&1 != nil))
      |> List.flatten
      |> Enum.join("\n")
  end

  def insert(entity) do
    module      = elem(entity, 0)
    table       = entity.model.__ecto__(:name)
    primary_key = module.__ecto__(:primary_key)
    pk_value    = entity.primary_key

    zipped = module.__ecto__(:entity_kw, entity, primary_key: !!pk_value)

    [ fields, values ] = List.unzip(zipped)

    "INSERT INTO #{table} (#{Enum.join(fields, ", ")})\n" <>
    "VALUES (#{Enum.map_join(values, ", ", &literal(&1))})"
  end

  def update(entity) do
    module   = elem(entity, 0)
    table    = entity.model.__ecto__(:name)
    pk_field = module.__ecto__(:primary_key)
    pk_value = entity.primary_key

    zipped = module.__ecto__(:entity_kw, entity, primary_key: false)

    zipped_sql = Enum.map_join(zipped, ", ", fn({k, v}) ->
      "#{k} = #{literal(v)}"
    end)

    "UPDATE #{table} SET #{zipped_sql}\n" <>
    "WHERE #{pk_field} = #{literal(pk_value)}"
  end

  def update_all(module, values) when is_atom(module) do
    update_all(Query[from: module], values)
  end

  def update_all(Query[] = query, values) do
    names  = NameResolution.create_names(query)
    entity = elem(names, 0)
    name   = elem(entity, 1)
    table  = query.from.__ecto__(:name)

    zipped_sql = Enum.map_join(values, ", ", fn({field, expr}) ->
      "#{field} = #{expr(expr, names)}"
    end)

    where = if query.wheres == [], do: "", else: "\n" <> where(query.wheres, names)

    "UPDATE #{table} #{name}\n" <>
    "SET #{zipped_sql}" <>
    where
  end

  def delete(entity) do
    module   = elem(entity, 0)
    table    = entity.model.__ecto__(:name)
    pk_field = module.__ecto__(:primary_key)
    pk_value = entity.primary_key

    "DELETE FROM #{table} WHERE #{pk_field} = #{literal(pk_value)}"
  end

  def delete_all(module) when is_atom(module) do
    delete_all(Query[from: module])
  end

  def delete_all(Query[] = query) do
    names  = NameResolution.create_names(query)
    entity = elem(names, 0)
    name   = elem(entity, 1)
    table  = query.from.__ecto__(:name)

    where = if query.wheres == [], do: "", else: "\n" <> where(query.wheres, names)

    "DELETE #{name} FROM #{table} AS #{name}#{where}"
  end

  defp select(expr, models) do
    QueryExpr[expr: expr] = Normalizer.normalize_select(expr)
    "SELECT #{select_clause(expr, models)}"
  end

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

  defp join(Query[] = query, models, used_names) do
    # We need to make sure that we get a unique name for each entity since
    # the same entity can be referenced multiple times in joins
    models_list = tuple_to_list(models)
    Enum.map_reduce(query.joins, used_names, fn(expr, names) ->
      JoinExpr[] = expr = Normalizer.normalize_join(expr, query)

      { model, name } = Enum.find(models_list, fn({ model, name }) ->
        model == expr.model and not name in names
      end)

      table = model.__ecto__(:name)
      on_sql = expr(expr.on.expr, models)
      qual = join_qual(expr.qual)

      { "#{qual}JOIN #{table} #{name} ON #{on_sql}", [name|names] }
    end) |> elem(0)
  end

  defp join_qual(nil), do: ""
  defp join_qual(:inner), do: "INNER "
  defp join_qual(:left), do: "LEFT OUTER "
  defp join_qual(:right), do: "RIGHT OUTER "
  defp join_qual(:full), do: "FULL OUTER "

  defp from(from, sources) do
    from_model = Util.model(from)
    source = tuple_to_list(sources) |> Enum.find(&(from_model == Util.model(&1)))
    { table, name } = Util.source(source)
    { "FROM #{table} #{name}", [name] }
  end

  defp where([], _), do: nil
  defp where(wheres, models), do: "WHERE #{boolean_expr(wheres, models)}"

  defp group_by([], _models), do: nil
  defp group_by(group_bys, models) do
    exprs = Enum.map_join(group_bys, ", ", fn(expr) ->
      Enum.map_join(expr.expr, ", ", fn({ var, field }) ->
        { _model, name } = Util.find_model(models, var)
        "#{name}.#{field}"
      end)
    end)

    "GROUP BY #{exprs}"
  end

  defp order_by([], _vars), do: nil
  defp order_by(order_bys, models) do
    exprs = Enum.map_join(order_bys, ", ", fn(expr) ->
      Enum.map_join(expr.expr, ", ", &order_by_expr(&1, models))
    end)

    "ORDER BY #{exprs}"
  end

  defp order_by_expr({ dir, var, field }, vars) do
    { _model, name } = Util.find_model(vars, var)
    str = "#{name}.#{field}"
    case dir do
      nil   -> str
      :asc  -> "#{str} ASC"
      :desc -> "#{str} DESC"
    end
  end

  defp limit(nil), do: nil
  defp limit(limit), do: "LIMIT #{limit}"

  defp offset(nil), do: nil
  defp offset(offset), do: "OFFSET #{offset}"

  defp boolean_expr(query_exprs, vars) do
    Enum.map_join(query_exprs, " AND ", fn(QueryExpr[expr: expr]) ->
      "(#{expr(expr, vars)})"
    end) || ""
  end

  defp expr({{ :., _, [{ :&, _, [_] } = var, field] }, [], []}, vars) when is_atom(field) do
    { _model, name } = Util.find_model(vars, var)
    "#{name}.#{field}"
  end

  defp expr({ :&, _, [_] } = var, vars) do
    { model, name } = Util.find_model(vars, var)
    entity = model.__ecto__(:entity)
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

  Enum.each(binary_ops, fn({key, val}) ->
    defp expr({ unquote(key), _, [left, right] }, vars) do
      binary_ops(left, right, vars, unquote(val))
    end
  end)

  Enum.each(functions, fn({key, val}) ->
    defp expr({ unquote(key), _, arg_list }, vars) do
      "#{unquote(val)}(#{Enum.map_join(arg_list, ", ", fn(arg) -> expr(arg, vars) end)})"
    end
  end)

  defp expr({ :+, _, [arg] }, vars) do
    "+#{expr(arg, vars)}"
  end

  defp expr({ :-, _, [arg] }, vars) do
    "-#{expr(arg, vars)}"
  end

  defp expr({ :in, _, [left, { :.., _, [first, last] }] }, vars) do
    "#{expr(left, vars)} BETWEEN #{expr(first, vars)} AND #{expr(last, vars)}"
  end

  defp expr({ :in, _, [left, Range[first: first, last: last]] }, vars) do
    "#{expr(left, vars)} BETWEEN #{expr(first, vars)} AND #{expr(last, vars)}"
  end

  defp expr({ :in, _, [left, right] }, vars) do
    "#{expr(left, vars)} IN (#{Enum.map_join(right, ", ", fn(arg) -> expr(arg, vars) end)})"
  end

  defp expr(literal, _vars), do: literal(literal)

  defp binary_ops(left, right, vars, join_by_string) do
    "#{op_to_binary(left, vars)} #{join_by_string} #{op_to_binary(right, vars)}"
  end

  defp op_to_binary({ op, _, [_, _] } = expr, vars) when op in @binary_ops do
    "(#{expr(expr, vars)})"
  end

  defp op_to_binary(expr, vars) do
    expr(expr, vars)
  end

  defp literal(nil), do: "NULL"

  defp literal(true), do: "TRUE"
  defp literal(false), do: "FALSE"

  defp literal(item) when is_number(item), do: "#{item}"

  defp literal(item) when is_binary(item), do: "'#{escape_string(item)}'"

  defp literal(Ecto.DateTime[] = datetime) do
    "'#{datetime.year}-#{datetime.month}-#{datetime.day} #{datetime.hour}:#{datetime.min}:#{datetime.sec}'"
  end

  defp escape_string(value) when is_binary(value) do
    value
      |> :binary.replace("\\", "\\\\", [:global])
      |> :binary.replace("'", "''", [:global])
  end
end
