if Code.ensure_loaded?(Postgrex.Connection) do
  defmodule Ecto.Adapters.Postgres.SQL do
    @moduledoc false

    # This module handles the generation of SQL code from queries and for create,
    # update and delete. All queries have to be normalized and validated for
    # correctness before given to this module.

    alias Ecto.Query.QueryExpr
    alias Ecto.Query.JoinExpr
    alias Ecto.Query.Util


    binary_ops =
      [==: "=", !=: "!=", <=: "<=", >=: ">=", <:  "<", >:  ">",
       and: "AND", or: "OR",
       ilike: "ILIKE", like: "LIKE"]

    @binary_ops Dict.keys(binary_ops)

    Enum.map(binary_ops, fn {op, str} ->
      defp handle_fun(unquote(op), 2), do: {:binary_op, unquote(str)}
    end)

    defp handle_fun(fun, _arity), do: {:fun, Atom.to_string(fun)}

    defp quote_table(table), do: "\"#{table}\""
    defp quote_column(column), do: "\"#{column}\""

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
      {limit,    external} = limit(query.limit,        %{state | external: external})
      {offset,   external} = offset(query.offset,      %{state | external: external})

      from   = from(sources)
      lock   = lock(query.lock)

      sql =
        [select, from, join, where, group_by, having, order_by, limit, offset, lock]
        |> Enum.filter(&(&1 != nil))
        |> List.flatten
        |> Enum.join(" ")

      {sql, Map.values(external)}
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
          " (" <> Enum.map_join(fields, ", ", &quote_column(&1)) <> ") " <>
          "VALUES (" <> Enum.map_join(1..length(values), ", ", &"$#{&1}") <> ")"
      end

      if !Enum.empty?(returning) do
        sql = sql <> " RETURNING " <> Enum.map_join(returning, ", ", &quote_column(&1))
      end

      {sql, values}
    end

    # Generate SQL for an update statement
    def update(model) do
      module   = model.__struct__
      table    = module.__schema__(:source)
      pk_field = module.__schema__(:primary_key)
      pk_value = Map.get(model, pk_field)

      {fields, values} = module.__schema__(:keywords, model, primary_key: false)
                         |> :lists.unzip

      fields = Enum.with_index(fields)
      sql_sets = Enum.map_join(fields, ", ", fn {k, ix} ->
        "#{quote_column(k)} = $#{ix+1}"
      end)

      sql =
        "UPDATE #{quote_table(table)} SET " <> sql_sets <> " " <>
        "WHERE #{quote_column(pk_field)} = $#{length(values)+1}"

      {sql, values ++ [pk_value]}
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
      where = if where, do: " " <> where, else: ""

      sql =
        "UPDATE #{quote_table(table)} AS #{name} " <>
        "SET " <> zipped_sql <>
        where

      {sql, Map.values(external)}
    end

    # Generate SQL for a delete statement
    def delete(model) do
      module   = model.__struct__
      table    = module.__schema__(:source)
      pk_field = module.__schema__(:primary_key)
      pk_value = Map.get(model, pk_field)

      sql = "DELETE FROM #{quote_table(table)} WHERE #{quote_column(pk_field)} = $1"
      {sql, [pk_value]}
    end

    # Generate SQL for an delete all statement
    def delete_all(query) do
      names           = create_names(query)
      from            = elem(names, 0)
      {table, name}   = Util.source(from)
      state           = new_state(names, %{})
      {sql, external} = where(query.wheres, state)

      sql = if query.wheres == [], do: "", else: " " <> sql
      sql = "DELETE FROM #{quote_table(table)} AS #{name}" <> sql
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

    defp limit(nil, state), do: {nil, state.external}
    defp limit(%Ecto.Query.QueryExpr{expr: expr, external: external}, state) do
      expr_state = %{state | external: external, offset: Map.size(state.external)}
      {"LIMIT " <> expr(expr, expr_state), join_external(state.external, external)}
    end

    defp offset(nil, state), do: {nil, state.external}
    defp offset(%Ecto.Query.QueryExpr{expr: expr, external: external}, state) do
      expr_state = %{state | external: external, offset: Map.size(state.external)}
      {"OFFSET " <> expr(expr, expr_state), join_external(state.external, external)}
    end

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

    defp expr({arg, _, []}, state) when is_tuple(arg) do
      expr(arg, state)
    end

    defp expr(%Ecto.Query.Fragment{parts: parts}, state) do
      Enum.map_join(parts, "", fn
        part when is_binary(part) -> part
        expr -> expr(expr, state)
      end)
    end

    defp expr({:^, [], [ix]}, state) do
      param_index = state.offset + ix + 1
      value = Map.fetch!(state.external, ix)

      # We don't know the resulting postgres type from the elixir value `nil`
      # therefore we cannot send it as a parameter, because all parameters
      # require a type. Instead send it as a plain-text NULL and let postgres
      # infer the type.

      cond do
        is_nil(value) ->
          "NULL"
        true ->
          "$#{param_index}"
      end
    end

    defp expr({:., _, [{:&, _, [_]} = var, field]}, state) when is_atom(field) do
      {_, name} = Util.find_source(state.sources, var) |> Util.source
      "#{name}.#{quote_column(field)}"
    end

    defp expr({:&, _, [_]} = var, state) do
      source    = Util.find_source(state.sources, var)
      model     = Util.model(source)
      fields    = model.__schema__(:field_names)
      {_, name} = Util.source(source)

      Enum.map_join(fields, ", ", &"#{name}.#{quote_column(&1)}")
    end

    defp expr({:in, _, [left, right]}, state) do
      expr(left, state) <> " = ANY (" <> expr(right, state) <> ")"
    end

    defp expr({:is_nil, _, [arg]}, state) do
      "#{expr(arg, state)} IS NULL"
    end

    defp expr({:not, _, [expr]}, state) do
      "NOT (" <> expr(expr, state) <> ")"
    end

    defp expr({fun, _, args}, state) when is_atom(fun) and is_list(args) do
      case handle_fun(fun, length(args)) do
        {:binary_op, op} ->
          [left, right] = args
          op_to_binary(left, state) <>
          " #{op} "
          <> op_to_binary(right, state)

        {:fun, fun} ->
          "#{fun}(" <> Enum.map_join(args, ", ", &expr(&1, state)) <> ")"
      end
    end

    defp expr(list, state) when is_list(list) do
      "ARRAY[" <> Enum.map_join(list, ", ", &expr(&1, state)) <> "]"
    end

    defp expr(%Ecto.Tagged{value: binary, type: :binary}, _state) when is_binary(binary) do
      hex = Base.encode16(binary, case: :lower)
      "'\\x#{hex}'"
    end

    defp expr(%Ecto.Tagged{value: expr, type: :binary}, state) do
      expr(expr, state)
    end

    defp expr(%Ecto.Tagged{value: binary, type: :uuid}, _state) when is_binary(binary) do
      hex = Base.encode16(binary, case: :lower)
      "'#{hex}'"
    end

    defp expr(%Ecto.Tagged{value: expr, type: :uuid}, state) do
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
end
