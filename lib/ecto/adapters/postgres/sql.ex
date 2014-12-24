if Code.ensure_loaded?(Postgrex.Connection) do
  defmodule Ecto.Adapters.Postgres.SQL do
    @moduledoc false

    # This module handles the generation of SQL code from queries and for create,
    # update and delete. All queries have to be normalized and validated for
    # correctness before given to this module.

    alias Ecto.Query.SelectExpr
    alias Ecto.Query.QueryExpr
    alias Ecto.Query.JoinExpr
    alias Ecto.Query.Util
    alias Ecto.Migration.Table
    alias Ecto.Migration.Index

    # Generate a select statement for all
    def all(query) do
      # Generate SQL for every query expression type and combine to one string
      sources = create_names(query)

      from     = from(sources)
      select   = select(query.select, query.distincts, sources)
      join     = join(query.joins, sources)
      where    = where(query.wheres, sources)
      group_by = group_by(query.group_bys, sources)
      having   = having(query.havings, sources)
      order_by = order_by(query.order_bys, sources)
      limit    = limit(query.limit, sources)
      offset   = offset(query.offset, sources)
      lock     = lock(query.lock)

      [select, from, join, where, group_by, having, order_by, limit, offset, lock]
      |> Enum.filter(&(&1 != nil))
      |> Enum.join(" ")
    end

    # Generate SQL for an update all statement
    def update_all(query, values) do
      sources = create_names(query)
      {table, name, _model} = elem(sources, 0)

      zipped_sql = Enum.map_join(values, ", ", fn {field, expr} ->
        "#{quote_name(field)} = #{expr(expr, sources)}"
      end)

      where = where(query.wheres, sources)
      where = if where, do: " " <> where, else: ""

      "UPDATE #{quote_name(table)} AS #{name} " <>
      "SET " <> zipped_sql <>
      where
    end

    # Generate SQL for an delete all statement
    def delete_all(query) do
      sources = create_names(query)
      {table, name, _model} = elem(sources, 0)

      where = where(query.wheres, sources)
      where = if where, do: " " <> where, else: ""
      "DELETE FROM #{quote_name(table)} AS #{name}" <> where
    end

    # Generate SQL for an insert statement
    def insert(table, fields, returning) do
      values =
        if fields == [] do
          "DEFAULT VALUES"
        else
          "(" <> Enum.map_join(fields, ", ", &quote_name(&1)) <> ") " <>
          "VALUES (" <> Enum.map_join(1..length(fields), ", ", &"$#{&1}") <> ")"
        end

      "INSERT INTO #{quote_name(table)} " <> values <> returning(returning)
    end

    # Generate SQL for an update statement
    def update(table, filters, fields, returning) do
      {filters, count} = Enum.map_reduce filters, 1, fn field, acc ->
        {"#{quote_name(field)} = $#{acc}", acc + 1}
      end

      {fields, _count} = Enum.map_reduce fields, count, fn field, acc ->
        {"#{quote_name(field)} = $#{acc}", acc + 1}
      end

      "UPDATE #{quote_name(table)} SET " <> Enum.join(fields, ", ") <>
      " WHERE " <> Enum.join(filters, " AND ") <>
      returning(returning)
    end

    # Generate SQL for a delete statement
    def delete(table, filters) do
      {filters, _} = Enum.map_reduce filters, 1, fn field, acc ->
        {"#{quote_name(field)} = $#{acc}", acc + 1}
      end

      "DELETE FROM #{quote_name(table)} WHERE " <> Enum.join(filters, " AND ")
    end

    ## Helpers

    defp quote_name(name), do: "\"#{name}\""

    defp returning([]),
      do: ""
    defp returning(returning),
      do: " RETURNING " <> Enum.map_join(returning, ", ", &quote_name/1)

    ## Query generation

    binary_ops =
      [==: "=", !=: "!=", <=: "<=", >=: ">=", <:  "<", >:  ">",
       and: "AND", or: "OR",
       ilike: "ILIKE", like: "LIKE"]

    @binary_ops Keyword.keys(binary_ops)

    Enum.map(binary_ops, fn {op, str} ->
      defp handle_fun(unquote(op), 2), do: {:binary_op, unquote(str)}
    end)

    defp handle_fun(fun, _arity), do: {:fun, Atom.to_string(fun)}

    defp select(%SelectExpr{fields: fields}, [], sources) do
      "SELECT " <> Enum.map_join(fields, ", ", &expr(&1, sources))
    end

    defp select(%SelectExpr{fields: fields}, distincts, sources) do
      exprs =
        Enum.map_join(distincts, ", ", fn
          %QueryExpr{expr: expr} ->
            Enum.map_join(expr, ", ", &expr(&1, sources))
        end)

      "SELECT DISTINCT ON (" <> exprs <> ") " <>
        Enum.map_join(fields, ", ", &expr(&1, sources))
    end

    defp from(sources) do
      {table, name, _model} = elem(sources, 0)
      "FROM #{quote_name(table)} AS #{name}"
    end

    defp join([], _sources), do: nil
    defp join(joins, sources) do
      joins = Enum.with_index(joins)
      Enum.map_join(joins, " ", fn
        {%JoinExpr{on: %QueryExpr{expr: expr}, qual: qual}, ix} ->
          {table, name, _model} = elem(sources, ix+1)

          on   = expr(expr, sources)
          qual = join_qual(qual)

          "#{qual} JOIN #{quote_name(table)} AS #{name} ON " <> on
      end)
    end

    defp join_qual(:inner), do: "INNER"
    defp join_qual(:left),  do: "LEFT OUTER"
    defp join_qual(:right), do: "RIGHT OUTER"
    defp join_qual(:full),  do: "FULL OUTER"

    defp where(wheres, sources) do
      boolean("WHERE", wheres, sources)
    end

    defp having(havings, sources) do
      boolean("HAVING", havings, sources)
    end

    defp group_by([], _sources), do: nil
    defp group_by(group_bys, sources) do
      "GROUP BY " <>
        Enum.map_join(group_bys, ", ", fn
          %QueryExpr{expr: expr} ->
            Enum.map_join(expr, ", ", &expr(&1, sources))
        end)
    end

    defp order_by([], _sources), do: nil
    defp order_by(order_bys, sources) do
      "ORDER BY " <>
        Enum.map_join(order_bys, ", ", fn
          %QueryExpr{expr: expr} ->
            Enum.map_join(expr, ", ", &order_by_expr(&1, sources))
        end)
    end

    defp order_by_expr({dir, expr}, sources) do
      str = expr(expr, sources)
      case dir do
        :asc  -> str
        :desc -> str <> " DESC"
      end
    end

    defp limit(nil, _sources), do: nil
    defp limit(%Ecto.Query.QueryExpr{expr: expr}, sources) do
      "LIMIT " <> expr(expr, sources)
    end

    defp offset(nil, _sources), do: nil
    defp offset(%Ecto.Query.QueryExpr{expr: expr}, sources) do
      "OFFSET " <> expr(expr, sources)
    end

    defp lock(nil), do: nil
    defp lock(false), do: nil
    defp lock(true), do: "FOR UPDATE"
    defp lock(lock_clause), do: lock_clause

    defp boolean(_name, [], _sources), do: nil
    defp boolean(name, query_exprs, sources) do
      name <> " " <>
        Enum.map_join(query_exprs, " AND ", fn
          %QueryExpr{expr: expr} ->
            "(" <> expr(expr, sources) <> ")"
        end)
    end

    defp expr({:^, [], [ix]}, _sources) do
      "$#{ix+1}"
    end

    defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources) when is_atom(field) do
      {_, name, _} = elem(sources, idx)
      "#{name}.#{quote_name(field)}"
    end

    defp expr({:&, _, [idx]}, sources) do
      {_table, name, model} = elem(sources, idx)
      fields = model.__schema__(:fields)
      Enum.map_join(fields, ", ", &"#{name}.#{quote_name(&1)}")
    end

    defp expr({:in, _, [left, right]}, sources) do
      expr(left, sources) <> " = ANY (" <> expr(right, sources) <> ")"
    end

    defp expr({:is_nil, _, [arg]}, sources) do
      "#{expr(arg, sources)} IS NULL"
    end

    defp expr({:not, _, [expr]}, sources) do
      "NOT (" <> expr(expr, sources) <> ")"
    end

    defp expr({:fragment, _, parts}, sources) do
      Enum.map_join(parts, "", fn
        part when is_binary(part) -> part
        expr -> expr(expr, sources)
      end)
    end

    defp expr({fun, _, args}, sources) when is_atom(fun) and is_list(args) do
      case handle_fun(fun, length(args)) do
        {:binary_op, op} ->
          [left, right] = args
          op_to_binary(left, sources) <>
          " #{op} "
          <> op_to_binary(right, sources)

        {:fun, fun} ->
          "#{fun}(" <> Enum.map_join(args, ", ", &expr(&1, sources)) <> ")"
      end
    end

    defp expr(list, sources) when is_list(list) do
      "ARRAY[" <> Enum.map_join(list, ", ", &expr(&1, sources)) <> "]"
    end

    defp expr(%Ecto.Query.Tagged{value: binary, type: :binary}, _sources) when is_binary(binary) do
      hex = Base.encode16(binary, case: :lower)
      "'\\x#{hex}'"
    end

    defp expr(%Ecto.Query.Tagged{value: binary, type: :uuid}, _sources) when is_binary(binary) do
      hex = Base.encode16(binary)
      "'#{hex}'"
    end

    defp expr(nil, _sources),   do: "NULL"
    defp expr(true, _sources),  do: "TRUE"
    defp expr(false, _sources), do: "FALSE"

    defp expr(literal, _sources) when is_binary(literal) do
      "'#{escape_string(literal)}'"
    end

    defp expr(literal, _sources) when is_integer(literal) do
      String.Chars.Integer.to_string(literal)
    end

    defp expr(literal, _sources) when is_float(literal) do
      String.Chars.Float.to_string(literal) <> "::float"
    end

    defp op_to_binary({op, _, [_, _]} = expr, sources) when op in @binary_ops do
      "(" <> expr(expr, sources) <> ")"
    end

    defp op_to_binary(expr, sources) do
      expr(expr, sources)
    end

    defp escape_string(value) when is_binary(value) do
      :binary.replace(value, "'", "''", [:global])
    end

    defp create_names(query) do
      sources = query.sources |> Tuple.to_list
      Enum.reduce(sources, [], fn {table, model}, names ->
        name = unique_name(names, String.first(table), 0)
        [{table, name, model}|names]
      end) |> Enum.reverse |> List.to_tuple
    end

    # Brute force find unique name
    defp unique_name(names, name, counter) do
      counted_name = name <> Integer.to_string(counter)
      if Enum.any?(names, fn {_, n, _} -> n == counted_name end) do
        unique_name(names, name, counter + 1)
      else
        counted_name
      end
    end

    # DDL
    def migrate({:create, %Table{}=table, columns}) do
      "CREATE TABLE #{quote_name(table.name)} (#{column_definitions(columns)})"
    end

    def migrate({:drop, %Table{name: name}}) do
      "DROP TABLE #{quote_name(name)}"
    end

    def migrate({:create, %Index{}=index}) do
      ["CREATE#{if index.unique, do: " UNIQUE"}", "INDEX", quote_name(Index.format_name(index)), "ON", quote_name(index.table), "(#{Enum.map_join(index.columns, ", ", &quote_name/1)})"]
        |> Enum.join(" ")
    end

    def migrate({:drop, %Index{}=index}) do
      "DROP INDEX #{quote_name(Index.format_name(index))}"
    end

    def migrate({:alter, %Table{}=table, changes}) do
      "ALTER TABLE #{quote_name(table.name)} #{column_changes(changes)}"
    end

    def migrate(default) when is_bitstring(default), do: default

    def object_exists_query({:column, {table_name, column_name}}) do
      "SELECT count(1) FROM information_schema.columns WHERE table_name = '#{table_name}' AND column_name = '#{column_name}'"
    end

    def object_exists_query({:table, table_name}) do
      "SELECT count(1) FROM information_schema.tables WHERE table_name = '#{table_name}'"
    end

    defp column_definitions(columns) do
      Enum.map_join(columns, ", ", &column_definition/1)
    end

    defp column_definition({:add, name, type, _opts}), do: "#{quote_name(name)} #{column_type(type)}"

    defp column_changes(columns) do
      Enum.map_join(columns, ", ", &column_change/1)
    end

    defp column_change({:add, name, type, _opts}),    do: "ADD COLUMN #{quote_name(name)} #{column_type(type)}"
    defp column_change({:modify, name, type, _opts}), do: "ALTER COLUMN #{quote_name(name)} TYPE #{column_type(type)}"
    defp column_change({:remove, name}),              do: "DROP COLUMN #{quote_name(name)}"
    defp column_change({:rename, from, to}),          do: "RENAME COLUMN #{quote_name(from)} TO #{quote_name(to)}"

    @column_types %{
      primary_key: "serial primary key",
      string: "varchar",
      datetime: "timestamp",
      binary: "bytea"
    }

    defp column_type({:references, foreign_table, foreign_column, type}), do: "#{column_type(type)} REFERENCES #{quote_name(foreign_table)}(#{quote_name(foreign_column)})"
    defp column_type({:array, type}), do: column_type(type) <> "[]"
    defp column_type(type), do: @column_types[type] || type
  end
end
