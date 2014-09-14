defmodule Ecto.Adapters.Mysql.SQL do
  @moduledoc false

  # This module handles the generation of SQL code from queries and for create,
  # update and delete. All queries have to be normalized and validated for
  # correctness before given to this module.

  alias Ecto.Query.QueryExpr
  alias Ecto.Query.JoinExpr
  alias Ecto.Query.Util

  unary_ops = [ -: "-", +: "+" ]

  binary_ops =
    [ ==: "=", !=: "!=", <=: "<=", >=: ">=", <:  "<", >:  ">",
      and: "AND", or: "OR",
      +:  "+", -:  "-", *:  "*",
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

  defp quote_table(table), do: "`#{table}`"

  defp quote_column(column), do: "`#{column}`"

  # Generate SQL for a select statement
  def select(query) do
    # Generate SQL for every query expression type and combine to one string
    sources = create_names(query)
    state   = new_state(sources, %{})

    {select,   external} = select(query.select, query.distincts, state)
    {join,     external} = join(query,               %{state | external: external})
    {where,    external} = where(query.wheres,       %{state | external: external})
    {group_by, external} = group_by(query.group_bys, %{state | external: external})
    {having,   external} = having(query.havings,     %{state | external: external})
    {order_by, external} = order_by(query.order_bys, %{state | external: external})

    from   = from(sources)
    limit  = limit(query.limit)
    offset = offset(query.offset)
    lock   = lock(query.lock)

    sql =
      [select, from, join, where, group_by, having, order_by, limit, offset, lock]
      |> Enum.filter(&(&1 != nil))
      |> List.flatten
      |> Enum.join("\n")

    {sql, List.flatten(Map.values(external))}
  end

  # Generate SQL for an insert statement
  def insert(model, _returning) do
    module = model.__struct__
    table  = module.__schema__(:source)

    {fields, values} = module.__schema__(:keywords, model)
      |> Enum.filter(fn {_, val} -> val != nil end)
      |> :lists.unzip

    sql = "INSERT INTO #{quote_table(table)}"

    if fields == [] do
      sql = sql <> " VALUES ()"
    else
      sql = sql <>
        " (" <> Enum.map_join(fields, ", ", &quote_column(&1)) <> ")\n" <>
        "VALUES (" <> Enum.map_join(1..length(values), ", ", fn _x -> "?" end) <> ")"
    end

    {sql, List.flatten(values)}
  end

  # Generate SQL for an update statement
  def update(model) do
    module   = model.__struct__
    table    = module.__schema__(:source)
    pk_field = module.__schema__(:primary_key)
    pk_value = Map.get(model, pk_field)

    model_values = module.__schema__(:keywords, model, primary_key: false)

    sql_sets = Enum.map_join(model_values, ", ", fn {k, v} ->
      if v == nil do
        "#{quote_column(k)} = NULL"
      else
        "#{quote_column(k)} = ?"
      end
    end)

    values = 
      Enum.map(model_values, fn {_, v} -> v end)
        |> Enum.filter(fn v -> v != nil end)

    sql =
      "UPDATE #{quote_table(table)} SET " <> sql_sets <> "\n" <>
      "WHERE #{quote_column(pk_field)} = ?"

    {sql, List.flatten(values) ++ [pk_value]}
  end

  # Generate SQL for an update all statement
  def update_all(query, values, external) do
    names         = create_names(query)
    from          = elem(names, 0)
    {table, name} = Util.source(from)
    state         = new_state(names, external, 0)

    zipped_sql = Enum.map_join(values, ", ", fn {field, expr} ->
      "#{quote_column(field)} = #{expr(expr, state)}"
    end)

    {where, external} = where(query.wheres, state)
    where = if where, do: "\n" <> where, else: ""

    sql =
      "UPDATE #{quote_table(table)} AS #{name}\n" <>
      "SET " <> zipped_sql <>
      where

    {sql, List.flatten(Map.values(external))}
  end

  # Generate SQL for a delete statement
  def delete(model) do
    module   = model.__struct__
    table    = module.__schema__(:source)
    pk_field = module.__schema__(:primary_key)
    pk_value = Map.get(model, pk_field)

    sql = "DELETE FROM #{quote_table(table)} WHERE #{quote_column(pk_field)} = ?"
    {sql, [pk_value]}
  end

  # Generate SQL for an delete all statement
  def delete_all(query) do
    names           = create_names(query)
    from            = elem(names, 0)
    {table, name}   = Util.source(from)
    state           = new_state(names, %{})
    {sql, external} = where(query.wheres, state)

    sql = if query.wheres == [], do: "", else: "\n" <> sql
    sql = "DELETE #{name} FROM #{quote_table(table)} AS #{name}" <> sql
    {sql, Map.values(external)}
  end

  defp select(%QueryExpr{expr: expr, external: right}, [], %{external: external} = state) do
    state = %{state | external: right, offset: Map.size(external)}
    sql   = "SELECT " <> select_clause(expr, state)
    {sql, join_external(external, right)}
  end

  defp select(%QueryExpr{expr: expr, external: right}, distincts, state) do
    {exprs, external} =
      Enum.map_reduce(distincts, state.external, fn
        %QueryExpr{expr: expr, external: right}, left ->
          state = %{state | external: right, offset: Map.size(left)}
          sql = Enum.map_join(expr, ", ", &expr(&1, state))
          {sql, join_external(left, right)}
      end)

    exprs = Enum.join(exprs, ", ")
    state = %{state | external: right, offset: Map.size(external)}
    sql   = "SELECT DISTINCT ON (" <> exprs <> ") " <>
            select_clause(expr, state)
    {sql, join_external(external, right)}
  end

  defp from(sources) do
    {table, name} = elem(sources, 0) |> Util.source
    "FROM #{quote_table(table)} AS #{name}"
  end

  defp join(query, state) do
    joins = Stream.with_index(query.joins)
    Enum.map_reduce(joins, state.external, fn
      {%JoinExpr{on: %QueryExpr{expr: expr, external: right}, qual: qual}, ix}, left ->
        source        = elem(state.sources, ix+1)
        {table, name} = Util.source(source)

        state = %{state | external: right, offset: Map.size(left)}
        on_sql = expr(expr, state)
        qual   = join_qual(qual)
        sql    = "#{qual} JOIN #{quote_table(table)} AS #{name} ON " <> on_sql
        {sql, join_external(left, right)}
    end)
  end

  defp join_qual(:inner), do: "INNER"
  defp join_qual(:left),  do: "LEFT OUTER"
  defp join_qual(:right), do: "RIGHT OUTER"
  defp join_qual(:full),  do: "FULL OUTER"

  defp where(wheres, state) do
    boolean("WHERE", wheres, state)
  end

  defp having(havings, state) do
    boolean("HAVING", havings, state)
  end

  defp group_by([], state), do: {nil, state.external}

  defp group_by(group_bys, state) do
    {exprs, external} =
      Enum.map_reduce(group_bys, state.external, fn
        %QueryExpr{expr: expr, external: right}, left ->
          state = %{state | external: right, offset: Map.size(left)}
          sql   = Enum.map_join(expr, ", ", &expr(&1, state))
          {sql, join_external(left, right)}
      end)

    exprs = Enum.join(exprs, ", ")
    sql   = "GROUP BY " <> exprs
    {sql, external}
  end

  defp order_by([], state), do: {nil, state.external}

  defp order_by(order_bys, state) do
    {exprs, external} =
      Enum.map_reduce(order_bys, state.external, fn
        %QueryExpr{expr: expr, external: right}, left ->
          state = %{state | external: right, offset: Map.size(left)}
          sql   = Enum.map_join(expr, ", ", &order_by_expr(&1, state))
          {sql, join_external(left, right)}
      end)

    exprs = Enum.join(exprs, ", ")
    sql = "ORDER BY " <> exprs
    {sql, external}
  end

  defp order_by_expr({dir, expr}, state) do
    str = expr(expr, state)
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

  defp boolean(_name, [], state), do: {nil, state.external}

  defp boolean(name, query_exprs, state) do
    {exprs, external} =
      Enum.map_reduce(query_exprs, state.external, fn
        %QueryExpr{expr: expr, external: right}, left ->
          state = %{state | external: right, offset: Map.size(left)}
          expr  = "(" <> expr(expr, state) <> ")"
          {expr, join_external(left, right)}
      end)

    exprs = Enum.join(exprs, " AND ")
    {name <> " " <> exprs, external}
  end

  defp expr({:^, [], [ix]}, state) do
    value       = Map.fetch!(state.external, ix)

    if is_list(value) do
      Enum.map_join(1..length(value), ", ", fn _x -> "?" end)
    else
      "?"
    end
  end

  defp expr({:., _, [{:&, _, [_]} = var, field]}, state) when is_atom(field) do
    {_, name} = Util.find_source(state.sources, var) |> Util.source
    "#{name}.#{quote_column(field)}"
  end

  defp expr({:!, _, [expr]}, state) do
    "NOT (" <> expr(expr, state) <> ")"
  end

  defp expr({:&, _, [_]} = var, state) do
    source    = Util.find_source(state.sources, var)
    model     = Util.model(source)
    fields    = model.__schema__(:field_names)
    {_, name} = Util.source(source)

    Enum.map_join(fields, ", ", &"#{name}.#{quote_column(&1)}")
  end

  defp expr({:==, _, [nil, right]}, state) do
    "#{op_to_binary(right, state)} IS NULL"
  end

  defp expr({:==, _, [left, nil]}, state) do
    "#{op_to_binary(left, state)} IS NULL"
  end

  defp expr({:!=, _, [nil, right]}, state) do
    "#{op_to_binary(right, state)} IS NOT NULL"
  end

  defp expr({:!=, _, [left, nil]}, state) do
    "#{op_to_binary(left, state)} IS NOT NULL"
  end

  defp expr({:in, _, [left, first .. last]}, state) do
    sqls = [expr(left, state),
            "BETWEEN",
            expr(first, state),
            "AND",
            expr(last, state)]
    Enum.join(sqls, " ")
  end

  defp expr({:in, _, [left, {:.., _, [first, last]}]}, state) do
    sqls = [expr(left, state),
            "BETWEEN",
            expr(first, state),
            "AND",
            expr(last, state)]
    Enum.join(sqls, " ")
  end

  defp expr({:in, _, [left, right]}, state) do
    expr(left, state) <> " IN (" <> expr(right, state) <> ")"
  end

  defp expr((_ .. _) = range, state) do
    expr(Enum.to_list(range), state)
  end

  defp expr({:.., _, [first, last]}, state) do
    expr(Enum.to_list(first..last), state)
  end

  defp expr({:/, _, [left, right]}, state) do
    op_to_binary(left, state) <>
    " / " <>
    op_to_binary(right, state)
  end

  defp expr({arg, _, []}, state) when is_tuple(arg) do
    expr(arg, state)
  end

  defp expr({:date, _, [datetime]}, state) do
    expr(datetime, state)
  end

  defp expr({:time, _, [datetime]}, state) do
    expr(datetime, state)
  end

  defp expr({:datetime, _, [date, time]}, state) do
    "(#{expr(date, state)} + #{expr(time, state)})"
  end

    # <>: "||", ++: "||",
  defp expr({:<>, _, [left, right]}, state) do
    "CONCAT(" <>
    op_to_binary(left, state) <>
    "," <>
    op_to_binary(right, state) <>
    ")"
  end

  defp expr({:++, _, [left, right]}, state) do
    "CONCAT(" <>
    op_to_binary(left, state) <>
    "," <>
    op_to_binary(right, state) <>
    ")"
  end

  defp expr({fun, _, args}, state) when is_atom(fun) and is_list(args) do
    case translate_name(fun, length(args)) do
      {:unary_op, op} ->
        arg = expr(List.first(args), state)
        op <> arg

      {:binary_op, op} ->
        [left, right] = args
        op_to_binary(left, state) <>
        " #{op} "
        <> op_to_binary(right, state)

      {:fun, "localtimestamp"} ->
        "localtimestamp"

      {:fun, fun} ->
        "#{fun}(" <> Enum.map_join(args, ", ", &expr(&1, state)) <> ")"
    end
  end


  defp expr(%Ecto.Tagged{value: expr, type: {:array, _inner}}, state) do
    state = %{state | external_type: false}
    expr(expr, state)
  end

  defp expr(%Ecto.Tagged{value: binary, type: :binary}, _state)
      when is_binary(binary) do
    hex = Base.encode16(binary, case: :lower)
    "X'#{hex}'"
  end

  defp expr(%Ecto.Tagged{value: expr, type: :binary}, state) do
    state = %{state | external_type: false}
    expr(expr, state)
  end

  defp expr(nil, _state), do: "NULL"

  defp expr(true, _state), do: "TRUE"

  defp expr(false, _state), do: "FALSE"

  defp expr(literal, _state) when is_binary(literal) do
    "'#{escape_string(literal)}'"
  end

  defp expr(literal, _state) when is_integer(literal) do
    to_string(literal)
  end

  defp expr(literal, _state) when is_float(literal) do
    to_string(literal)
  end

  defp op_to_binary({op, _, [_, _]} = expr, state) when op in @binary_ops do
    "(" <> expr(expr, state) <> ")"
  end

  defp op_to_binary(expr, state) do
    expr(expr, state)
  end

  defp select_clause(expr, state) do
    flatten_select(expr) |> Enum.map_join(", ", &expr(&1, state))
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
  #defp type(:boolean),  do: "boolean"
  #defp type(:string),   do: "text"
  #defp type(:integer),  do: "integer"
  #defp type(:float),    do: "float"
  #defp type(:binary),   do: "bytea"
  #defp type(:date),     do: "date"
  #defp type(:time),     do: "time"
  #defp type(:datetime), do: "datetime"
  #defp type(:interval), do: "interval"
  #defp type(:decimal),  do: "decimal"

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

  defp join_external(left, right) do
    size = Map.size(left)
    for {ix, value} <- right,
        into: left,
        do: {size+ix, value}
  end

  defp new_state(sources, external, offset \\ nil) do
    %{external: external, offset: offset, sources: sources,
      external_type: true}
  end
end
