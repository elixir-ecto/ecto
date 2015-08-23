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

    def query(conn, sql, params, opts \\ []) do
      params = Enum.map params, fn
        %Ecto.Query.Tagged{value: value} -> value
        %{__struct__: _} = value -> value
        %{} = value -> json_library.encode!(value)
        value -> value
      end

      case Mariaex.Connection.query(conn, sql, params, opts) do
        {:ok, res}        -> {:ok, Map.from_struct(res)}
        {:error, _} = err -> err
      end
    end

    defp normalize_port(port) when is_binary(port), do: String.to_integer(port)
    defp normalize_port(port) when is_integer(port), do: port

    defp json_library do
      Application.get_env(:ecto, :json_library)
    end

    def to_constraints(%Mariaex.Error{mariadb: %{code: 1062, message: message}}) do
      case :binary.split(message, " for key ") do
        [_, quoted] -> [unique: strip_quotes(quoted)]
        _ -> []
      end
    end
    def to_constraints(%Mariaex.Error{mariadb: %{code: code, message: message}})
        when code in [1451, 1452] do
      case :binary.split(message, [" CONSTRAINT ", " FOREIGN KEY "], [:global]) do
        [_, quoted, _] -> [foreign_key: strip_quotes(quoted)]
        _ -> []
      end
    end
    def to_constraints(%Mariaex.Error{}),
      do: []

    defp strip_quotes(quoted) do
      size = byte_size(quoted) - 2
      <<_, unquoted::binary-size(size), _>> = quoted
      unquoted
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

    alias Ecto.Query
    alias Ecto.Query.SelectExpr
    alias Ecto.Query.QueryExpr
    alias Ecto.Query.JoinExpr

    def all(query) do
      sources = create_names(query)

      from     = from(sources)
      select   = select(query, sources)
      join     = join(query, sources)
      where    = where(query, sources)
      group_by = group_by(query, sources)
      having   = having(query, sources)
      order_by = order_by(query, sources)
      limit    = limit(query, sources)
      offset   = offset(query, sources)
      lock     = lock(query.lock)

      assemble([select, from, join, where, group_by, having, order_by, limit, offset, lock])
    end

    def update_all(query) do
      sources = create_names(query)
      {table, name, _model} = elem(sources, 0)

      update = "UPDATE #{table} AS #{name}"
      fields = update_fields(query, sources)
      join   = join(query, sources)
      where  = where(query, sources)

      assemble([update, join, "SET", fields, where])
    end

    def delete_all(query) do
      sources = create_names(query)
      {_table, name, _model} = elem(sources, 0)

      delete = "DELETE #{name}.*"
      from   = from(sources)
      join   = join(query, sources)
      where  = where(query, sources)

      assemble([delete, from, join, where])
    end

    def insert(prefix, table, [], _returning),
      do: "INSERT INTO #{quote_table(prefix, table)} () VALUES ()"
    def insert(prefix, table, fields, _returning) do
      values = ~s{(#{Enum.map_join(fields, ", ", &quote_name/1)}) } <>
               ~s{VALUES (#{Enum.map_join(1..length(fields), ", ", fn (_) -> "?" end)})}

      "INSERT INTO #{quote_table(prefix, table)} " <> values
    end

    def update(prefix, table, fields, filters, _returning) do
      filters = Enum.map filters, fn field  ->
        "#{quote_name(field)} = ?"
      end

      fields = Enum.map fields, fn field ->
        "#{quote_name(field)} = ?"
      end

      "UPDATE #{quote_table(prefix, table)} SET " <> Enum.join(fields, ", ") <>
        " WHERE " <> Enum.join(filters, " AND ")
    end

    def delete(prefix, table, filters, _returning) do
      filters = Enum.map filters, fn field ->
        "#{quote_name(field)} = ?"
      end

      "DELETE FROM #{quote_table(prefix, table)} WHERE " <>
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

    defp select(%Query{select: %SelectExpr{fields: fields}, distinct: distinct} = query,
                sources) do
      "SELECT " <>
        distinct(distinct, sources, query) <>
        Enum.map_join(fields, ", ", &expr(&1, sources, query))
    end

    defp distinct(nil, _sources, _query), do: ""
    defp distinct(%QueryExpr{expr: true}, _sources, _query),  do: "DISTINCT "
    defp distinct(%QueryExpr{expr: false}, _sources, _quety), do: ""
    defp distinct(%QueryExpr{expr: exprs}, _sources, query) when is_list(exprs) do
      error!(query, "DISTINCT with multiple columns is not supported by MySQL")
    end

    defp from(sources) do
      {table, name, _model} = elem(sources, 0)
      "FROM #{table} AS #{name}"
    end

    defp update_fields(%Query{updates: updates} = query, sources) do
      for(%{expr: expr} <- updates,
          {op, kw} <- expr,
          {key, value} <- kw,
          do: update_op(op, key, value, sources, query)) |> Enum.join(", ")
    end

    defp update_op(:set, key, value, sources, query) do
      quote_name(key) <> " = " <> expr(value, sources, query)
    end

    defp update_op(:inc, key, value, sources, query) do
      quoted = quote_name(key)
      quoted <> " = " <> quoted <> " + " <> expr(value, sources, query)
    end

    defp update_op(command, _key, _value, _sources, query) do
      error!(query, "Unknown update operation #{inspect command} for MySQL")
    end

    defp join(%Query{joins: []}, _sources), do: []
    defp join(%Query{joins: joins} = query, sources) do
      Enum.map_join(joins, " ", fn
        %JoinExpr{on: %QueryExpr{expr: expr}, qual: qual, ix: ix, source: source} ->
          {join, name, _model} = elem(sources, ix)
          qual = join_qual(qual)
          join = join || "(" <> expr(source, sources, query) <> ")"
          "#{qual} JOIN " <> join <> " AS #{name} ON " <> expr(expr, sources, query)
      end)
    end

    defp join_qual(:inner), do: "INNER"
    defp join_qual(:left),  do: "LEFT OUTER"
    defp join_qual(:right), do: "RIGHT OUTER"
    defp join_qual(:full),  do: "FULL OUTER"

    defp where(%Query{wheres: wheres} = query, sources) do
      boolean("WHERE", wheres, sources, query)
    end

    defp having(%Query{havings: havings} = query, sources) do
      boolean("HAVING", havings, sources, query)
    end

    defp group_by(%Query{group_bys: group_bys} = query, sources) do
      exprs =
        Enum.map_join(group_bys, ", ", fn
          %QueryExpr{expr: expr} ->
            Enum.map_join(expr, ", ", &expr(&1, sources, query))
        end)

      case exprs do
        "" -> []
        _  -> "GROUP BY " <> exprs
      end
    end

    defp order_by(%Query{order_bys: order_bys} = query, sources) do
      exprs =
        Enum.map_join(order_bys, ", ", fn
          %QueryExpr{expr: expr} ->
            Enum.map_join(expr, ", ", &order_by_expr(&1, sources, query))
        end)

      case exprs do
        "" -> []
        _  -> "ORDER BY " <> exprs
      end
    end

    defp order_by_expr({dir, expr}, sources, query) do
      str = expr(expr, sources, query)
      case dir do
        :asc  -> str
        :desc -> str <> " DESC"
      end
    end

    defp limit(%Query{limit: nil}, _sources), do: []
    defp limit(%Query{limit: %QueryExpr{expr: expr}} = query, sources) do
      "LIMIT " <> expr(expr, sources, query)
    end

    defp offset(%Query{offset: nil}, _sources), do: []
    defp offset(%Query{offset: %QueryExpr{expr: expr}} = query, sources) do
      "OFFSET " <> expr(expr, sources, query)
    end

    defp lock(nil), do: []
    defp lock(lock_clause), do: lock_clause

    defp boolean(_name, [], _sources, _query), do: []
    defp boolean(name, query_exprs, sources, query) do
      name <> " " <>
        Enum.map_join(query_exprs, " AND ", fn
          %QueryExpr{expr: expr} ->
            "(" <> expr(expr, sources, query) <> ")"
        end)
    end

    defp expr({:^, [], [_ix]}, _sources, _query) do
      "?"
    end

    defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources, _query)
        when is_atom(field) do
      {_, name, _} = elem(sources, idx)
      "#{name}.#{quote_name(field)}"
    end

    defp expr({:&, _, [idx]}, sources, query) do
      {table, name, model} = elem(sources, idx)
      unless model do
        error!(query, "MySQL requires a model when using selector " <>
          "#{inspect name} but only the table #{inspect table} was given. " <>
          "Please specify a model or specify exactly which fields from " <>
          "#{inspect name} you desire")
      end
      fields = model.__schema__(:fields)
      Enum.map_join(fields, ", ", &"#{name}.#{quote_name(&1)}")
    end

    defp expr({:in, _, [_left, []]}, _sources, _query) do
      "false"
    end

    defp expr({:in, _, [left, right]}, sources, query) when is_list(right) do
      args = Enum.map_join right, ",", &expr(&1, sources, query)
      expr(left, sources, query) <> " IN (" <> args <> ")"
    end

    defp expr({:in, _, [left, {:^, _, [ix, length]}]}, sources, query) do
      args = Enum.map_join(ix+1..ix+length, ",", fn (_) -> "?" end)
      expr(left, sources, query) <> " IN (" <> args <> ")"
    end

    defp expr({:in, _, [left, right]}, sources, query) do
      expr(left, sources, query) <> " = ANY(" <> expr(right, sources, query) <> ")"
    end

    defp expr({:is_nil, _, [arg]}, sources, query) do
      "#{expr(arg, sources, query)} IS NULL"
    end

    defp expr({:not, _, [expr]}, sources, query) do
      "NOT (" <> expr(expr, sources, query) <> ")"
    end

    defp expr({:fragment, _, [kw]}, _sources, query) when is_list(kw) or tuple_size(kw) == 3 do
      error!(query, "MySQL adapter does not support keyword or interpolated fragments")
    end

    defp expr({:fragment, _, parts}, sources, query) do
      Enum.map_join(parts, "", fn
        {:raw, part}  -> part
        {:expr, expr} -> expr(expr, sources, query)
      end)
    end

    defp expr({:datetime_add, _, [datetime, count, interval]}, sources, query) do
      "CAST(date_add(" <> expr(datetime, sources, query) <> ", "
                       <> interval(count, interval, sources, query) <> ") AS datetime)"
    end

    defp expr({:date_add, _, [date, count, interval]}, sources, query) do
      "CAST(date_add(" <> expr(date, sources, query) <> ", "
                       <> interval(count, interval, sources, query) <> ") AS date)"
    end

    defp expr({fun, _, args}, sources, query) when is_atom(fun) and is_list(args) do
      case handle_call(fun, length(args)) do
        {:binary_op, op} ->
          [left, right] = args
          op_to_binary(left, sources, query) <>
          " #{op} "
          <> op_to_binary(right, sources, query)

        {:fun, fun} ->
          "#{fun}(" <> Enum.map_join(args, ", ", &expr(&1, sources, query)) <> ")"
      end
    end

    defp expr(list, _sources, query) when is_list(list) do
      error!(query, "Array type is not supported by MySQL")
    end

    defp expr(%Decimal{} = decimal, _sources, _query) do
      Decimal.to_string(decimal, :normal)
    end

    defp expr(%Ecto.Query.Tagged{value: binary, type: :binary}, _sources, _query)
        when is_binary(binary) do
      hex = Base.encode16(binary, case: :lower)
      "x'#{hex}'"
    end

    defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources, query)
        when type in [:id, :integer, :float] do
      expr(other, sources, query)
    end

    defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources, query) do
      "CAST(#{expr(other, sources, query)} AS " <> ecto_to_db(type, query) <> ")"
    end

    defp expr(nil, _sources, _query),   do: "NULL"
    defp expr(true, _sources, _query),  do: "TRUE"
    defp expr(false, _sources, _query), do: "FALSE"

    defp expr(literal, _sources, _query) when is_binary(literal) do
      "'#{escape_string(literal)}'"
    end

    defp expr(literal, _sources, _query) when is_integer(literal) do
      String.Chars.Integer.to_string(literal)
    end

    defp expr(literal, _sources, _query) when is_float(literal) do
      # MySQL doesn't support float cast
      expr = String.Chars.Float.to_string(literal)
      "(0 + #{expr})"
    end

    defp interval(count, "millisecond", sources, query) do
      "INTERVAL (" <> expr(count, sources, query) <> " * 1000) microsecond"
    end

    defp interval(count, interval, sources, query) do
      "INTERVAL " <> expr(count, sources, query) <> " " <> interval
    end

    defp op_to_binary({op, _, [_, _]} = expr, sources, query) when op in @binary_ops do
      "(" <> expr(expr, sources, query) <> ")"
    end

    defp op_to_binary(expr, sources, query) do
      expr(expr, sources, query)
    end

    defp create_names(%{prefix: prefix, sources: sources}) do
      create_names(prefix, sources, 0, tuple_size(sources)) |> List.to_tuple()
    end

    defp create_names(prefix, sources, pos, limit) when pos < limit do
      current =
        case elem(sources, pos) do
          {table, model} ->
            name = String.first(table) <> Integer.to_string(pos)
            {quote_table(prefix, table), name, model}
          {:fragment, _, _} ->
            {nil, "f" <> Integer.to_string(pos), nil}
        end
      [current|create_names(prefix, sources, pos + 1, limit)]
    end

    defp create_names(_prefix, _sources, pos, pos) do
      []
    end

    ## DDL

    alias Ecto.Migration.Table
    alias Ecto.Migration.Index
    alias Ecto.Migration.Reference

    def execute_ddl({command, %Table{} = table, columns}) when command in [:create, :create_if_not_exists] do
      engine  = engine_expr(table.engine)
      options = options_expr(table.options)
      if_not_exists = if command == :create_if_not_exists, do: " IF NOT EXISTS", else: ""

      "CREATE TABLE" <> if_not_exists <>
        " #{quote_table(table.name)} (#{column_definitions(table, columns)})" <> engine <> options
    end

    def execute_ddl({command, %Table{name: name}}) when command in [:drop, :drop_if_exists] do
      if_exists = if command == :drop_if_exists, do: " IF EXISTS", else: ""

      "DROP TABLE" <> if_exists <> " #{quote_table(name)}"
    end

    def execute_ddl({:alter, %Table{}=table, changes}) do
      "ALTER TABLE #{quote_table(table.name)} #{column_changes(table, changes)}"
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

    def execute_ddl({:create_if_not_exists, %Index{}}),
      do: error!(nil, "MySQL adapter does not support create if not exists for index")

    def execute_ddl({:drop, %Index{}=index}) do
      assemble(["DROP INDEX",
                quote_name(index.name),
                "ON #{quote_table(index.table)}",
                if_do(index.concurrently, "LOCK=NONE")])
    end

    def execute_ddl({:drop_if_exists, %Index{}}),
      do: error!(nil, "MySQL adapter does not support drop if exists for index")

    def execute_ddl({:rename, %Table{}=current_table, %Table{}=new_table}) do
      "RENAME TABLE #{quote_table(current_table.name)} TO #{quote_table(new_table.name)}"
    end

    def execute_ddl({:rename, %Table{}=table, current_column, new_column}) do
      [
        "SELECT @column_type := COLUMN_TYPE FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '#{table.name}' AND COLUMN_NAME = '#{current_column}' LIMIT 1",
        "SET @rename_stmt = concat('ALTER TABLE `#{table.name}` CHANGE COLUMN `#{current_column}` `#{new_column}` ', @column_type)",
        "PREPARE rename_stmt FROM @rename_stmt",
        "EXECUTE rename_stmt"
      ]
    end

    def execute_ddl(string) when is_binary(string), do: string

    def execute_ddl(keyword) when is_list(keyword),
      do: error!(nil, "MySQL adapter does not support keyword lists in execute")

    defp column_definitions(table, columns) do
      Enum.map_join(columns, ", ", &column_definition(table, &1))
    end

    defp column_definition(table, {:add, name, %Reference{} = ref, opts}) do
      assemble([quote_name(name), reference_column_type(ref.type, opts),
                column_options(name, opts), reference_expr(ref, table, name)])
    end

    defp column_definition(_table, {:add, name, type, opts}) do
      assemble([quote_name(name), column_type(type, opts), column_options(name, opts)])
    end

    defp column_changes(table, columns) do
      Enum.map_join(columns, ", ", &column_change(table, &1))
    end

    defp column_change(table, {:add, name, %Reference{} = ref, opts}) do
      assemble(["ADD", quote_name(name), reference_column_type(ref.type, opts),
                column_options(name, opts), constraint_expr(ref, table, name)])
    end

    defp column_change(_table, {:add, name, type, opts}) do
      assemble(["ADD", quote_name(name), column_type(type, opts), column_options(name, opts)])
    end

    defp column_change(table, {:modify, name, %Reference{} = ref, opts}) do
      assemble([
        "MODIFY", quote_name(name), reference_column_type(ref.type, opts),
        column_options(name, opts), constraint_expr(ref, table, name)
      ])
    end

    defp column_change(_table, {:modify, name, type, opts}) do
      assemble(["MODIFY", quote_name(name), column_type(type, opts), column_options(name, opts)])
    end

    defp column_change(_table, {:remove, name}), do: "DROP #{quote_name(name)}"

    defp column_options(name, opts) do
      default = Keyword.fetch(opts, :default)
      null    = Keyword.get(opts, :null)
      pk      = Keyword.get(opts, :primary_key)

      [default_expr(default), null_expr(null), pk_expr(pk, name)]
    end

    defp pk_expr(true, name), do: ", PRIMARY KEY(#{quote_name(name)})"
    defp pk_expr(_, _), do: []

    defp null_expr(false), do: "NOT NULL"
    defp null_expr(true), do: "NULL"
    defp null_expr(_), do: []

    defp default_expr({:ok, nil}),
      do: "DEFAULT NULL"
    defp default_expr({:ok, literal}) when is_binary(literal),
      do: "DEFAULT '#{escape_string(literal)}'"
    defp default_expr({:ok, literal}) when is_number(literal) or is_boolean(literal),
      do: "DEFAULT #{literal}"
    defp default_expr({:ok, {:fragment, expr}}),
      do: "DEFAULT #{expr}"
    defp default_expr(:error),
      do: []

    defp index_expr(literal), do: quote_name(literal)

    defp engine_expr(nil),
      do: " ENGINE = INNODB"
    defp engine_expr(storage_engine),
      do: String.upcase(" ENGINE = #{storage_engine}")

    defp options_expr(nil),
      do: ""
    defp options_expr(keyword) when is_list(keyword),
      do: error!(nil, "MySQL adapter does not support keyword lists in :options")
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

    defp constraint_expr(%Reference{} = ref, table, name),
      do: ", ADD CONSTRAINT #{reference_name(ref, table, name)} " <>
          "FOREIGN KEY (#{quote_name(name)}) " <>
          "REFERENCES #{quote_name(ref.table)}(#{quote_name(ref.column)})" <>
          reference_on_delete(ref.on_delete)

    defp reference_expr(%Reference{} = ref, table, name),
      do: ", CONSTRAINT #{reference_name(ref, table, name)} FOREIGN KEY " <>
          "(#{quote_name(name)}) REFERENCES " <>
          "#{quote_table(ref.table)}(#{quote_name(ref.column)})" <>
          reference_on_delete(ref.on_delete)

    defp reference_name(%Reference{name: nil}, table, column),
      do: quote_name("#{table.name}_#{column}_fkey")
    defp reference_name(%Reference{name: name}, _table, _column),
      do: quote_name(name)

    defp reference_column_type(:serial, _opts), do: "BIGINT UNSIGNED"
    defp reference_column_type(type, opts), do: column_type(type, opts)

    defp reference_on_delete(:nilify_all), do: " ON DELETE SET NULL"
    defp reference_on_delete(:delete_all), do: " ON DELETE CASCADE"
    defp reference_on_delete(_), do: ""

    ## Helpers

    defp quote_name(name)
    defp quote_name(name) when is_atom(name),
      do: quote_name(Atom.to_string(name))
    defp quote_name(name) do
      if String.contains?(name, "`") do
        error!(nil, "bad field name #{inspect name}")
      end

      <<?`, name::binary, ?`>>
    end

    defp quote_table(nil, name),    do: quote_table(name)
    defp quote_table(prefix, name), do: quote_table(prefix) <> "." <> quote_table(name)

    defp quote_table(name) when is_atom(name),
      do: quote_table(Atom.to_string(name))
    defp quote_table(name) do
      if String.contains?(name, "`") do
        error!(nil, "bad table name #{inspect name}")
      end
      <<?`, name::binary, ?`>>
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

    defp ecto_to_db(type, query \\ nil)
    defp ecto_to_db({:array, _}, query),
      do: error!(query, "Array type is not supported by MySQL")
    defp ecto_to_db(:id, _query),        do: "integer"
    defp ecto_to_db(:binary_id, _query), do: "binary(16)"
    defp ecto_to_db(:string, _query),    do: "varchar"
    defp ecto_to_db(:float, _query),     do: "double"
    defp ecto_to_db(:binary, _query),    do: "blob"
    defp ecto_to_db(:uuid, _query),      do: "binary(16)" # MySQL does not support uuid
    defp ecto_to_db(:map, _query),       do: "text"
    defp ecto_to_db(other, _query),      do: Atom.to_string(other)

    defp error!(nil, message) do
      raise ArgumentError, message
    end
    defp error!(query, message) do
      raise Ecto.QueryError, query: query, message: message
    end
  end
end
