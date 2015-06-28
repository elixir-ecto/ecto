if Code.ensure_loaded?(Mariaex.Connection) do

  defmodule Ecto.Adapters.MySQL.Connection do
    @moduledoc false

    @default_port 3306
    @behaviour Ecto.Adapters.Connection
    @behaviour Ecto.Adapters.SQL.Query

    ## Connection

    def connect(opts) do
      opts = Keyword.update(opts, :port, @default_port, &normalize_port/1)
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

    def query(conn, sql, params, opts \\ []) do
      params = Enum.map params, fn
        %Ecto.Query.Tagged{value: value} -> value
        %{__struct__: _} = value -> value
        %{} = value -> json_library.encode!(value)
        value -> value
      end

      case Mariaex.Connection.query(conn, sql, params, opts) do
        {:ok, %Mariaex.Result{} = result} -> {:ok, Map.from_struct(result)}
        {:error, %Mariaex.Error{}} =  err -> err
      end
    end

    defp normalize_port(port) when is_binary(port), do: String.to_integer(port)
    defp normalize_port(port) when is_integer(port), do: port

    defp json_library do
      Application.get_env(:ecto, :json_library)
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
      select   = select(query.select, query.distinct, sources)
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

    def update_all(query) do
      sources = create_names(query)
      {table, name, _model} = elem(sources, 0)

      update = "UPDATE #{quote_table(table)} AS #{name}"
      fields = update_fields(query.updates, sources)
      join   = join(query.joins, sources)
      where  = where(query.wheres, sources)

      assemble([update, join, "SET", fields, where])
    end

    def delete_all(query) do
      sources = create_names(query)
      {_table, name, _model} = elem(sources, 0)

      delete = "DELETE #{name}.*"
      from   = from(sources)
      join   = join(query.joins, sources)
      where  = where(query.wheres, sources)

      assemble([delete, from, join, where])
    end

    def insert(table, [], _returning), do: "INSERT INTO #{quote_table(table)} () VALUES ()"
    def insert(table, fields, _returning) do
      values = ~s{(#{Enum.map_join(fields, ", ", &quote_name/1)}) } <>
               ~s{VALUES (#{Enum.map_join(1..length(fields), ", ", fn (_) -> "?" end)})}

      "INSERT INTO #{quote_table(table)} " <> values
    end

    def update(table, fields, filters, _returning) do
      filters = Enum.map filters, fn field  ->
        "#{quote_name(field)} = ?"
      end

      fields = Enum.map fields, fn field ->
        "#{quote_name(field)} = ?"
      end

      "UPDATE #{quote_table(table)} SET " <> Enum.join(fields, ", ") <>
        " WHERE " <> Enum.join(filters, " AND ")
    end

    def delete(table, filters, _returning) do
      filters = Enum.map filters, fn field ->
        "#{quote_name(field)} = ?"
      end

      "DELETE FROM #{quote_table(table)} WHERE " <>
        Enum.join(filters, " AND ")
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

    defp select(%SelectExpr{fields: fields}, distinct, sources) do
      "SELECT " <>
        distinct(distinct, sources) <>
        Enum.map_join(fields, ", ", &expr(&1, sources))
    end

    defp distinct(nil, _sources), do: ""
    defp distinct(%QueryExpr{expr: true}, _sources),  do: "DISTINCT "
    defp distinct(%QueryExpr{expr: false}, _sources), do: ""
    defp distinct(%QueryExpr{expr: exprs}, _sources) when is_list(exprs) do
      raise ArgumentError, "DISTINCT with multiple columns is not supported by MySQL"
    end

    defp from(sources) do
      {table, name, _model} = elem(sources, 0)
      "FROM #{quote_table(table)} AS #{name}"
    end

    defp update_fields(updates, sources) do
      for(%{expr: expr} <- updates,
          {op, kw} <- expr,
          {key, value} <- kw,
          do: update_op(op, key, value, sources)) |> Enum.join(", ")
    end

    defp update_op(:set, key, value, sources) do
      quote_name(key) <> " = " <> expr(value, sources)
    end

    defp update_op(:inc, key, value, sources) do
      quoted = quote_name(key)
      quoted <> " = " <> quoted <> " + " <> expr(value, sources)
    end

    defp update_op(command, _key, _value, _sources) do
      raise ArgumentError, "Unknown update operation #{inspect command} for MySQL"
    end

    defp join([], _sources), do: []
    defp join(joins, sources) do
      Enum.map_join(joins, " ", fn
        %JoinExpr{on: %QueryExpr{expr: expr}, qual: qual, ix: ix} ->
          {table, name, _model} = elem(sources, ix)

          on   = expr(expr, sources)
          qual = join_qual(qual)

          "#{qual} JOIN #{quote_table(table)} AS #{name} ON " <> on
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
        "" -> []
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
        "" -> []
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

    defp limit(nil, _sources), do: []
    defp limit(%Ecto.Query.QueryExpr{expr: expr}, sources) do
      "LIMIT " <> expr(expr, sources)
    end

    defp offset(nil, _sources), do: []
    defp offset(%Ecto.Query.QueryExpr{expr: expr}, sources) do
      "OFFSET " <> expr(expr, sources)
    end

    defp lock(nil), do: []
    defp lock(lock_clause), do: lock_clause

    defp boolean(_name, [], _sources), do: []
    defp boolean(name, query_exprs, sources) do
      name <> " " <>
        Enum.map_join(query_exprs, " AND ", fn
          %QueryExpr{expr: expr} ->
            "(" <> expr(expr, sources) <> ")"
        end)
    end

    defp expr({:^, [], [_ix]}, _sources) do
      "?"
    end

    defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources) when is_atom(field) do
      {_, name, _} = elem(sources, idx)
      "#{name}.#{quote_name(field)}"
    end

    defp expr({:&, _, [idx]}, sources) do
      {table, name, model} = elem(sources, idx)
      unless model do
        raise ArgumentError, "MySQL requires a model when using selector #{inspect name} but " <>
                             "only the table #{inspect table} was given. Please specify a model " <>
                             "or specify exactly which fields from #{inspect name} you desire"
      end
      fields = model.__schema__(:fields)
      Enum.map_join(fields, ", ", &"#{name}.#{quote_name(&1)}")
    end

    defp expr({:in, _, [_left, []]}, _sources) do
      "false"
    end

    defp expr({:in, _, [left, right]}, sources) when is_list(right) do
      args = Enum.map_join right, ",", &expr(&1, sources)
      expr(left, sources) <> " IN (" <> args <> ")"
    end

    defp expr({:in, _, [left, {:^, _, [ix, length]}]}, sources) do
      args = Enum.map_join(ix+1..ix+length, ",", fn (_) -> "?" end)
      expr(left, sources) <> " IN (" <> args <> ")"
    end

    defp expr({:in, _, [left, right]}, sources) do
      expr(left, sources) <> " = ANY(" <> expr(right, sources) <> ")"
    end

    defp expr({:is_nil, _, [arg]}, sources) do
      "#{expr(arg, sources)} IS NULL"
    end

    defp expr({:not, _, [expr]}, sources) do
      "NOT (" <> expr(expr, sources) <> ")"
    end

    defp expr({:fragment, _, [kw]}, _sources) when is_list(kw) or tuple_size(kw) == 3 do
      raise ArgumentError, "MySQL adapter does not support keyword or interpolated fragments"
    end

    defp expr({:fragment, _, parts}, sources) do
      Enum.map_join(parts, "", fn
        {:raw, part}  -> part
        {:expr, expr} -> expr(expr, sources)
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

    defp expr(list, _sources) when is_list(list) do
      raise ArgumentError, "Array type is not supported by MySQL"
    end

    defp expr(%Ecto.Query.Tagged{value: binary, type: :binary}, _sources) when is_binary(binary) do
      hex = Base.encode16(binary, case: :lower)
      "x'#{hex}'"
    end

    defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources) when type in [:id, :integer, :float] do
      expr(other, sources)
    end

    defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources) do
      "CAST(#{expr(other, sources)} AS " <> ecto_to_db(type) <> ")"
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
      # MySQL doesn't support float cast
      expr = String.Chars.Float.to_string(literal)
      "(0 + #{expr})"
    end

    defp op_to_binary({op, _, [_, _]} = expr, sources) when op in @binary_ops do
      "(" <> expr(expr, sources) <> ")"
    end

    defp op_to_binary(expr, sources) do
      expr(expr, sources)
    end

    defp create_names(%{sources: sources}) do
      create_names(sources, 0, tuple_size(sources)) |> List.to_tuple()
    end

    defp create_names(sources, pos, limit) when pos < limit do
      {table, model} = elem(sources, pos)
      name = String.first(table) <> Integer.to_string(pos)
      [{table, name, model}|create_names(sources, pos + 1, limit)]
    end

    defp create_names(_sources, pos, pos) do
      []
    end

    ## DDL

    alias Ecto.Migration.Table
    alias Ecto.Migration.Index
    alias Ecto.Migration.Reference

    def ddl_exists(%Table{name: name}) do
      """
      SELECT COUNT(1)
        FROM information_schema.tables
       WHERE table_schema = SCHEMA()
             AND table_name = '#{escape_string(to_string(name))}'
      """
    end

    def ddl_exists(%Index{name: name}) do
      """
      SELECT COUNT(1)
        FROM information_schema.statistics
       WHERE table_schema = SCHEMA()
         AND index_name = '#{escape_string(to_string(name))}'
      """
    end

    def execute_ddl({:create, %Table{} = table, columns}) do
      engine = engine_expr(table.engine)
      options = options_expr(table.options)

      "CREATE TABLE #{quote_table(table.name)} (#{column_definitions(columns)})" <> engine <> options
    end

    def execute_ddl({:drop, %Table{name: name}}) do
      "DROP TABLE #{quote_table(name)}"
    end

    def execute_ddl({:alter, %Table{}=table, changes}) do
      "ALTER TABLE #{quote_table(table.name)} #{column_changes(changes)}"
    end

    def execute_ddl({:create, %Index{}=index}) do
      create = "CREATE#{if index.unique, do: " UNIQUE"} INDEX"
      using  = if index.using, do: "USING #{index.using}", else: []

      assemble([create,
                quote_name(index.name),
                "ON",
                quote_table(index.table),
                "(#{Enum.map_join(index.columns, ", ", &index_expr/1)})",
                using,
                if_do(index.concurrently, "LOCK=NONE")])
    end

    def execute_ddl({:drop, %Index{}=index}) do
      assemble(["DROP INDEX",
                quote_name(index.name),
                "ON #{quote_table(index.table)}",
                if_do(index.concurrently, "LOCK=NONE")])
    end

    def execute_ddl(default) when is_binary(default), do: default

    defp column_definitions(columns) do
      Enum.map_join(columns, ", ", &column_definition/1)
    end

    defp column_definition({:add, name, %Reference{} = ref, opts}) do
      assemble([quote_name(name), reference_column_type(ref.type, opts),
                column_options(name, opts), reference_expr(ref, name)])
    end

    defp column_definition({:add, name, type, opts}) do
      assemble([quote_name(name), column_type(type, opts), column_options(name, opts)])
    end

    defp column_changes(columns) do
      Enum.map_join(columns, ", ", &column_change/1)
    end

    defp column_change({:add, name, type, opts}) do
      assemble(["ADD", quote_name(name), column_type(type, opts), column_options(name, opts)])
    end

    defp column_change({:modify, name, type, opts}) do
      assemble(["MODIFY", quote_name(name), column_type(type, opts)])
    end

    defp column_change({:remove, name}), do: "DROP #{quote_name(name)}"

    defp column_options(name, opts) do
      default = Keyword.get(opts, :default)
      null    = Keyword.get(opts, :null)
      pk      = Keyword.get(opts, :primary_key)

      [default_expr(default), null_expr(null), pk_expr(pk, name)]
    end

    defp pk_expr(true, name), do: ", PRIMARY KEY(#{quote_name(name)})"
    defp pk_expr(_, _), do: []

    defp null_expr(false), do: "NOT NULL"
    defp null_expr(_), do: []

    defp default_expr(nil),
      do: []
    defp default_expr(literal) when is_binary(literal),
      do: "DEFAULT '#{escape_string(literal)}'"
    defp default_expr(literal) when is_number(literal) or is_boolean(literal),
      do: "DEFAULT #{literal}"
    defp default_expr({:fragment, expr}),
      do: "DEFAULT #{expr}"

    defp index_expr(literal), do: quote_name(literal)

    defp reference_expr(%Reference{} = ref, foreign_key_name),
      do: ", FOREIGN KEY (#{quote_name(foreign_key_name)}) REFERENCES " <>
          "#{quote_table(ref.table)} (#{quote_name(ref.column)})" <>
          reference_on_delete(ref.on_delete)

    defp engine_expr(nil),
      do: " ENGINE = INNODB"
    defp engine_expr(storage_engine),
      do: String.upcase(" ENGINE = #{storage_engine}")

    defp options_expr(nil),
      do: ""
    defp options_expr(options),
      do: " #{options}"

    defp column_type(type, opts) do
      size      = Keyword.get(opts, :size)
      precision = Keyword.get(opts, :precision)
      scale     = Keyword.get(opts, :scale)
      type_name = ecto_to_db(type)

      cond do
        size            -> "#{type_name}(#{size})"
        precision       -> "#{type_name}(#{precision},#{scale || 0})"
        type == :string -> "#{type_name}(255)"
        true            -> "#{type_name}"
      end
    end

    defp reference_column_type(:serial, _opts), do: "BIGINT UNSIGNED"
    defp reference_column_type(type, opts), do: column_type(type, opts)

    defp reference_on_delete(:nilify_all), do: " ON DELETE SET NULL"
    defp reference_on_delete(:delete_all), do: " ON DELETE CASCADE"
    defp reference_on_delete(_), do: ""

    ## Helpers

    defp quote_name(name) when is_atom(name), do: quote_name(Atom.to_string(name))
    defp quote_name(name) do
      if String.contains?(name, "`") do
        raise ArgumentError, "bad field name #{inspect name}"
      end

      <<?`, name::binary, ?`>>
    end

    defp quote_table(name) when is_atom(name), do: quote_table(Atom.to_string(name))
    defp quote_table(name) do
      if String.contains?(name, "`") do
        raise ArgumentError, "bad table name #{inspect name}"
      end

      <<?`, String.replace(name, ".", "`.`")::binary, ?`>>
    end

    defp assemble(list) do
      list
      |> List.flatten
      |> Enum.join(" ")
    end

    defp if_do(condition, value) do
      if condition, do: value, else: []
    end

    defp escape_string(value) when is_binary(value) do
      value
      |> :binary.replace("'", "''", [:global])
      |> :binary.replace("\\", "\\\\", [:global])
    end

    defp ecto_to_db({:array, _}), do: raise(ArgumentError, "Array type is not supported by MySQL")
    defp ecto_to_db(:id),         do: "integer"
    defp ecto_to_db(:binary_id),  do: "binary(16)"
    defp ecto_to_db(:string),     do: "varchar"
    defp ecto_to_db(:float),      do: "double"
    defp ecto_to_db(:binary),     do: "blob"
    defp ecto_to_db(:uuid),       do: "binary(16)" # MySQL does not support uuid
    defp ecto_to_db(:map),        do: "text"
    defp ecto_to_db(other),       do: Atom.to_string(other)
  end
end
