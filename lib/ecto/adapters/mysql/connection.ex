if Code.ensure_loaded?(Mariaex.Connection) do

  defmodule Ecto.Adapters.MySQL.Connection do
    @moduledoc false
  
    @default_port 3306
    @behaviour Ecto.Adapters.SQL.Connection
  
    ## Connection
  
    def connect(opts) do
      opts = Keyword.put_new(opts, :port, @default_port)
      Mariaex.Connection.start_link(opts)
    end
  
    def disconnect(conn) do
      try do
        Mariaex.Connection.stop(conn)
      catch
        :exit, {:noproc, _} -> :ok
      end
      :ok
    end
  
    def query(conn, sql, params, opts) do
      case Mariaex.Connection.query(conn, sql, params, opts) do
        :ok -> :ok
        {:ok, %Mariaex.Result{} = result} -> {:ok, Map.from_struct(result)} 
        {:error, %Mariaex.Error{}} = err -> err
      end
    end
  
    ## Transaction

    def begin_transaction do
      "BEGIN"
    end

    def rollback do
      "ROLLBACK"
    end

    def commit do
      "COMMIT"
    end

    def savepoint(savepoint) do
      "SAVEPOINT " <> savepoint
    end

    def rollback_to_savepoint(savepoint) do
      "ROLLBACK TO SAVEPOINT " <> savepoint
    end

    ## Query

    alias Ecto.Query.SelectExpr
    alias Ecto.Query.QueryExpr
    alias Ecto.Query.JoinExpr

    def all(query) do
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

      assemble([select, from, join, where, group_by, having, order_by, limit, offset, lock])
    end

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

    def delete_all(query) do
      sources = create_names(query)
      {table, _name, _model} = elem(sources, 0)
      where = where(query.wheres, {})
      where = if where, do: " " <> where, else: ""
      "DELETE FROM #{quote_name(table)}" <> where
    end

    def insert(table, fields, returning) do
      values =
        if fields == [] do
          "DEFAULT VALUES"
        else
          "(" <> Enum.map_join(fields, ", ", &quote_name(&1)) <> ") " <>
          "VALUES (" <> Enum.map_join(1..length(fields), ", ", &"$#{&1}") <> ")"
        end

      "INSERT INTO #{quote_name(table)} " <> values <> 
      returning(returning)
    end

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

    def delete(table, filters, returning) do
      {filters, _} = Enum.map_reduce filters, 1, fn field, acc ->
        {"#{quote_name(field)} = $#{acc}", acc + 1}
      end

      "DELETE FROM #{quote_name(table)} WHERE " <> Enum.join(filters, " AND ") <>
        returning(returning) 
    end

    ## Query generation

    binary_ops =
      [==: "=", !=: "!=", <=: "<=", >=: ">=", <:  "<", >:  ">",
       and: "AND", or: "OR",
       ilike: "ILIKE", like: "LIKE"]

    @binary_ops Keyword.keys(binary_ops)

    Enum.map(binary_ops, fn {op, str} ->
      defp handle_call(unquote(op), 2), do: {:binary_op, unquote(str)}
    end)

    defp handle_call(fun, _arity), do: {:fun, Atom.to_string(fun)}

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
      Enum.map_join(joins, " ", fn
        %JoinExpr{on: %QueryExpr{expr: expr}, qual: qual, ix: ix} ->
          {table, name, _model} = elem(sources, ix)

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

    defp group_by(group_bys, sources) do
      exprs =
        Enum.map_join(group_bys, ", ", fn
          %QueryExpr{expr: expr} ->
            Enum.map_join(expr, ", ", &expr(&1, sources))
        end)

      case exprs do
        "" -> nil
        _  -> "GROUP BY " <> exprs
      end
    end

    defp order_by(order_bys, sources) do
      exprs =
        Enum.map_join(order_bys, ", ", fn
          %QueryExpr{expr: expr} ->
            Enum.map_join(expr, ", ", &order_by_expr(&1, sources))
        end)

      case exprs do
        "" -> nil
        _  -> "ORDER BY " <> exprs
      end
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
      case handle_call(fun, length(args)) do
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

    defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources) do
      expr(other, sources) <> "::" <> ecto_to_db(type)
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

    defp returning([]),
      do: "" 
    defp returning(returning), 
      do: raise "`RETURNING` clause not supported by MySQL"			

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

    alias Ecto.Migration.Table
    alias Ecto.Migration.Index
    alias Ecto.Migration.Reference

    def ddl_exists(%Table{name: name}) do
      """
      SELECT count(1) FROM information_schema.tables 
       WHERE table_schema = database() 
             AND table_name = '#{escape_string(to_string(name))}'
      """
    end

    def ddl_exists(%Index{name: name}) do
      """
      SELECT count(1) FROM information_schema.statistics 
       WHERE table_schema = database()
             AND index_name = '#{escape_string(to_string(name))}'
      """
    end

    def execute_ddl({:create, %Table{}=table, columns}) do
      sql = "CREATE TABLE #{quote_name(table.name)} (#{column_definitions(columns)})"
      IO.inspect sql
      sql
    end

    def execute_ddl({:drop, %Table{name: name}}) do
      "DROP TABLE #{quote_name(name)}"
    end

    def execute_ddl({:alter, %Table{}=table, changes}) do
      "ALTER TABLE #{quote_name(table.name)} #{column_changes(changes)}"
    end

    def execute_ddl({:create, %Index{}=index}) do
      assemble(["CREATE#{if index.unique, do: " UNIQUE"} INDEX",
                quote_name(index.name), "ON", quote_name(index.table),
                "(#{Enum.map_join(index.columns, ", ", &index_expr/1)})"])
    end

    def execute_ddl({:drop, %Index{}=index}) do
      "DROP INDEX #{quote_name(index.name)}"
    end

    def execute_ddl(default) when is_binary(default), do: default

    defp column_definitions(columns) do
      Enum.map_join(columns, ", ", &column_definition/1)
    end

    defp column_definition({:add, name, type, opts}) do
      assemble([quote_name(name), column_type(type, opts), column_options(opts)])
    end

    defp column_changes(columns) do
      Enum.map_join(columns, ", ", &column_change/1)
    end

    defp column_change({:add, name, type, opts}) do
      assemble(["ADD COLUMN", quote_name(name), column_type(type, opts), column_options(opts)])
    end

    defp column_change({:modify, name, type, opts}) do
      assemble(["ALTER COLUMN", quote_name(name), "TYPE", column_type(type, opts), column_options(opts)])
    end

    defp column_change({:remove, name}), do: "DROP COLUMN #{quote_name(name)}"

    defp column_options(opts) do
      default = Keyword.get(opts, :default)
      null    = Keyword.get(opts, :null)
      pk      = Keyword.get(opts, :primary_key)

      [default_expr(default), null_expr(null), pk_expr(pk)]
    end

    defp pk_expr(true), do: "PRIMARY KEY"
    defp pk_expr(_), do: nil

    defp null_expr(false), do: "NOT NULL"
    defp null_expr(true), do: "NULL"
    defp null_expr(_), do: nil

    defp default_expr(nil),
      do: nil
    defp default_expr(literal) when is_binary(literal),
      do: "DEFAULT '#{escape_string(literal)}'"
    defp default_expr(literal),
      do: "DEFAULT #{literal}"

    defp index_expr(literal) when is_binary(literal),
      do: literal
    defp index_expr(literal),
      do: quote_name(literal)

    defp column_type(%Reference{} = ref, opts),
      do: "#{column_type(ref.type, opts)} REFERENCES #{quote_name(ref.table)}(#{quote_name(ref.column)})"
    defp column_type({:array, type}, opts),
      do: column_type(type, opts) <> "[]"
    defp column_type(type, opts) do
      size      = Keyword.get(opts, :size)
      precision = Keyword.get(opts, :precision)
      scale     = Keyword.get(opts, :scale)
      type_name = ecto_to_db(type)

      IO.inspect type_name
      cond do
        size      -> "#{type_name}(#{size})"
        precision -> "#{type_name}(#{precision},#{scale || 0})"
        true      -> default_size(type_name)
      end
    end

    ## Helpers

    defp default_size("varchar"), do: "varchar(255)"
    defp default_size(type_name), do: type_name

    defp quote_name(name), do: "`#{name}`"

    defp assemble(list) do
      list
      |> List.flatten
      |> Enum.filter(&(&1 != nil))
      |> Enum.join(" ")
    end

    defp escape_string(value) when is_binary(value) do
      :binary.replace(value, "'", "''", [:global])
    end
 
    defp ecto_to_db(:string),   do: "varchar"
    defp ecto_to_db(:datetime), do: "timestamp"
    defp ecto_to_db(:binary),   do: "bytea"
    defp ecto_to_db(other),     do: Atom.to_string(other)
  end
end
