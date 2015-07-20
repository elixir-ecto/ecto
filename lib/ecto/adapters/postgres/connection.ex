if Code.ensure_loaded?(Postgrex.Connection) do

  defmodule Ecto.Adapters.Postgres.Connection do
    @moduledoc false

    @default_port 5432
    @behaviour Ecto.Adapters.Connection
    @behaviour Ecto.Adapters.SQL.Query

    ## Connection

    def connect(opts) do
      json = Application.get_env(:ecto, :json_library)
      extensions = [{Ecto.Adapters.Postgres.DateTime, []},
                    {Postgrex.Extensions.JSON, library: json}]

      opts =
        opts
        |> Keyword.update(:extensions, extensions, &(&1 ++ extensions))
        |> Keyword.update(:port, @default_port, &normalize_port/1)

      Postgrex.Connection.start_link(opts)
    end

    def query(conn, sql, params, opts) do
      params = Enum.map params, fn
        %Ecto.Query.Tagged{value: value} -> value
        value -> value
      end

      case Postgrex.Connection.query(conn, sql, params, opts) do
        {:ok, res}        -> {:ok, Map.from_struct(res)}
        {:error, _} = err -> err
      end
    end

    defp normalize_port(port) when is_binary(port), do: String.to_integer(port)
    defp normalize_port(port) when is_integer(port), do: port

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
      sources        = create_names(query)
      distinct_exprs = distinct_exprs(query, sources)

      from     = from(sources)
      select   = select(query, distinct_exprs, sources)
      join     = join(query, sources)
      where    = where(query, sources)
      group_by = group_by(query, sources)
      having   = having(query, sources)
      order_by = order_by(query, distinct_exprs, sources)
      limit    = limit(query, sources)
      offset   = offset(query, sources)
      lock     = lock(query.lock)

      assemble([select, from, join, where, group_by, having, order_by, limit, offset, lock])
    end

    def update_all(query) do
      sources = create_names(query)

      fields = update_fields(query, sources)
      update = update_expr(query, elem(sources, 0))
      join   = update_filter(query, sources)
      where  = where(query, sources)

      assemble([update, "SET", fields, join, where])
    end

    def delete_all(query) do
      sources = create_names(query)
      {table, name, _model} = elem(sources, 0)

      join  = using(query, sources)
      where = delete_all_where(query.joins, query, sources)

      assemble(["DELETE FROM #{table} AS #{name}", join, where])
    end

    def insert(prefix, table, fields, returning) do
      values =
        if fields == [] do
          "DEFAULT VALUES"
        else
          "(" <> Enum.map_join(fields, ", ", &quote_name/1) <> ") " <>
          "VALUES (" <> Enum.map_join(1..length(fields), ", ", &"$#{&1}") <> ")"
        end

      "INSERT INTO #{quote_table(prefix, table)} " <> values <> returning(returning)
    end

    def update(prefix, table, fields, filters, returning) do
      {fields, count} = Enum.map_reduce fields, 1, fn field, acc ->
        {"#{quote_name(field)} = $#{acc}", acc + 1}
      end

      {filters, _count} = Enum.map_reduce filters, count, fn field, acc ->
        {"#{quote_name(field)} = $#{acc}", acc + 1}
      end

      "UPDATE #{quote_table(prefix, table)} SET " <> Enum.join(fields, ", ") <>
        " WHERE " <> Enum.join(filters, " AND ") <>
        returning(returning)
    end

    def delete(prefix, table, filters, returning) do
      {filters, _} = Enum.map_reduce filters, 1, fn field, acc ->
        {"#{quote_name(field)} = $#{acc}", acc + 1}
      end

      "DELETE FROM #{quote_table(prefix, table)} WHERE " <>
        Enum.join(filters, " AND ") <> returning(returning)
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
                distinct_exprs, sources) do
      "SELECT " <>
        distinct(distinct, distinct_exprs) <>
        Enum.map_join(fields, ", ", &expr(&1, sources, query))
    end

    defp distinct_exprs(%Query{distinct: %QueryExpr{expr: exprs}} = query, sources)
        when is_list(exprs) do
      Enum.map_join(exprs, ", ", &expr(&1, sources, query))
    end
    defp distinct_exprs(_, _), do: ""

    defp distinct(nil, _sources), do: ""
    defp distinct(%QueryExpr{expr: true}, _exprs),  do: "DISTINCT "
    defp distinct(%QueryExpr{expr: false}, _exprs), do: ""
    defp distinct(_query, exprs), do: "DISTINCT ON (" <> exprs <> ") "

    defp from(sources) do
      {table, name, _model} = elem(sources, 0)
      "FROM #{table} AS #{name}"
    end

    defp using(%Query{joins: []}, _sources), do: []
    defp using(%Query{joins: joins} = query, sources) do
      Enum.map_join(joins, " ", fn
        %JoinExpr{on: %QueryExpr{expr: expr}, ix: ix} ->
          {table, name, _model} = elem(sources, ix)
          where = expr(expr, sources, query)
          "USING #{table} AS #{name} WHERE " <> where
      end)
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

    defp update_op(:push, key, value, sources, query) do
      quoted = quote_name(key)
      quoted <> " = array_append(" <> quoted <> ", " <> expr(value, sources, query) <> ")"
    end

    defp update_op(:pull, key, value, sources, query) do
      quoted = quote_name(key)
      quoted <> " = array_remove(" <> quoted <> ", " <> expr(value, sources, query) <> ")"
    end

    defp update_op(command, _key, _value, _sources, query) do
      error!(query, "Unknown update operation #{inspect command} for PostgreSQL")
    end

    defp update_expr(%Query{joins: []}, {table, name, _model}) do
      "UPDATE #{table} AS #{name}"
    end
    defp update_expr(_query, {table, _name, _model}) do
      "UPDATE #{table}"
    end

    defp update_filter(%Query{joins: []}, _sources), do: []
    defp update_filter(query, sources) do
      from(sources) <> " "  <> join(query, sources)
    end

    defp join(%Query{joins: []}, _sources), do: []
    defp join(%Query{joins: joins} = query, sources) do
      Enum.map_join(joins, " ", fn
        %JoinExpr{on: %QueryExpr{expr: expr}, qual: qual, ix: ix} ->
          {table, name, _model} = elem(sources, ix)

          on   = expr(expr, sources, query)
          qual = join_qual(qual)

          "#{qual} JOIN #{table} AS #{name} ON " <> on
      end)
    end

    defp join_qual(:inner), do: "INNER"
    defp join_qual(:left),  do: "LEFT OUTER"
    defp join_qual(:right), do: "RIGHT OUTER"
    defp join_qual(:full),  do: "FULL OUTER"

    defp delete_all_where([], query, sources), do: where(query, sources)
    defp delete_all_where(_joins, %Query{wheres: wheres} = query, sources) do
      boolean("AND", wheres, sources, query)
    end

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

    defp order_by(%Query{order_bys: order_bys} = query, distinct_exprs, sources) do
      exprs =
        Enum.map_join(order_bys, ", ", fn
          %QueryExpr{expr: expr} ->
            Enum.map_join(expr, ", ", &order_by_expr(&1, sources, query))
        end)

      case {distinct_exprs, exprs} do
        {_, ""} ->
          []
        {"", _} ->
          "ORDER BY " <> exprs
        {_, _}  ->
          "ORDER BY " <> distinct_exprs <> ", " <> exprs
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

    defp expr({:^, [], [ix]}, _sources, _query) do
      "$#{ix+1}"
    end

    defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources, _query) when is_atom(field) do
      {_, name, _} = elem(sources, idx)
      "#{name}.#{quote_name(field)}"
    end

    defp expr({:&, _, [idx]}, sources, query) do
      {table, name, model} = elem(sources, idx)
      unless model do
        error!(query, "PostgreSQL requires a model when using selector " <>
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
      args = Enum.map_join ix+1..ix+length, ",", &"$#{&1}"
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
      error!(query, "PostgreSQL adapter does not support keyword or interpolated fragments")
    end

    defp expr({:fragment, _, parts}, sources, query) do
      Enum.map_join(parts, "", fn
        {:raw, part}  -> part
        {:expr, expr} -> expr(expr, sources, query)
      end)
    end

    defp expr({:datetime_add, _, [datetime, count, interval]}, sources, query) do
      "(" <> expr(datetime, sources, query) <> "::timestamp + "
          <> interval(count, interval, sources, query) <> ")::timestamp"
    end

    defp expr({:date_add, _, [date, count, interval]}, sources, query) do
      "(" <> expr(date, sources, query) <> "::date + "
          <> interval(count, interval, sources, query) <> ")::date"
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

    defp expr(list, sources, query) when is_list(list) do
      "ARRAY[" <> Enum.map_join(list, ",", &expr(&1, sources, query)) <> "]"
    end

    defp expr(%Decimal{} = decimal, _sources, _query) do
      Decimal.to_string(decimal, :normal)
    end

    defp expr(%Ecto.Query.Tagged{value: binary, type: :binary}, _sources, _query)
        when is_binary(binary) do
      hex = Base.encode16(binary, case: :lower)
      "'\\x#{hex}'::bytea"
    end

    defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources, query) do
      expr(other, sources, query) <> "::" <> ecto_to_db(type)
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
      String.Chars.Float.to_string(literal) <> "::float"
    end

    defp interval(count, interval, _sources, _query) when is_integer(count) do
      "interval '" <> String.Chars.Integer.to_string(count) <> " " <> interval <> "'"
    end

    defp interval(count, interval, _sources, _query) when is_float(count) do
      count = :erlang.float_to_binary(count, [:compact, decimals: 16])
      "interval '" <> count <> " " <> interval <> "'"
    end

    defp interval(count, interval, sources, query) do
      "(" <> expr(count, sources, query) <> "::numeric * "
          <> interval(1, interval, sources, query) <> ")"
    end

    defp op_to_binary({op, _, [_, _]} = expr, sources, query) when op in @binary_ops do
      "(" <> expr(expr, sources, query) <> ")"
    end

    defp op_to_binary(expr, sources, query) do
      expr(expr, sources, query)
    end

    defp returning([]),
      do: ""
    defp returning(returning),
      do: " RETURNING " <> Enum.map_join(returning, ", ", &quote_name/1)

    defp create_names(%{prefix: prefix, sources: sources}) do
      create_names(prefix, sources, 0, tuple_size(sources)) |> List.to_tuple()
    end

    defp create_names(prefix, sources, pos, limit) when pos < limit do
      {table, model} = elem(sources, pos)
      name = String.first(table) <> Integer.to_string(pos)
      [{quote_table(prefix, table), name, model}|
        create_names(prefix, sources, pos + 1, limit)]
    end

    defp create_names(_prefix, _sources, pos, pos) do
      []
    end

    # DDL

    alias Ecto.Migration.Table
    alias Ecto.Migration.Index
    alias Ecto.Migration.Reference

    def ddl_exists(%Table{name: name}) do
      """
      SELECT count(1) FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE c.relkind IN ('r','v','m')
             AND c.relname = '#{escape_string(to_string(name))}'
             AND n.nspname = ANY (current_schemas(false))
      """
    end

    def ddl_exists(%Index{name: name}) do
      """
      SELECT count(1) FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE c.relkind IN ('i')
             AND c.relname = '#{escape_string(to_string(name))}'
             AND n.nspname = ANY (current_schemas(false))
      """
    end

    def execute_ddl({:create, %Table{}=table, columns}) do
      options = options_expr(table.options)
      "CREATE TABLE #{quote_table(table.name)} (#{column_definitions(columns)})" <> options
    end

    def execute_ddl({:drop, %Table{name: name}}) do
      "DROP TABLE #{quote_table(name)}"
    end

    def execute_ddl({:alter, %Table{}=table, changes}) do
      "ALTER TABLE #{quote_table(table.name)} #{column_changes(changes)}"
    end

    def execute_ddl({:create, %Index{}=index}) do
      fields = Enum.map_join(index.columns, ", ", &index_expr/1)

      assemble(["CREATE",
                if_do(index.unique, "UNIQUE"),
                "INDEX",
                if_do(index.concurrently, "CONCURRENTLY"),
                quote_name(index.name),
                "ON",
                quote_table(index.table),
                if_do(index.using, "USING #{index.using}"),
                "(#{fields})"])
    end

    def execute_ddl({:drop, %Index{}=index}) do
      assemble(["DROP",
                "INDEX",
                if_do(index.concurrently, "CONCURRENTLY"),
                quote_name(index.name)])
    end

    def execute_ddl({:rename, %Table{}=current_table, %Table{}=new_table}) do
      "ALTER TABLE #{quote_table(current_table.name)} RENAME TO #{quote_table(new_table.name)}"
    end

    def execute_ddl(string) when is_binary(string), do: string

    def execute_ddl(keyword) when is_list(keyword),
      do: error!(nil, "PostgreSQL adapter does not support keyword lists in execute")

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

    defp column_change({:modify, name, %Reference{} = ref, opts}) do
      assemble([
        "ALTER COLUMN", quote_name(name), "TYPE", reference_column_type(ref.type, opts),
        ", ADD CONSTRAINT", quote_name("#{name}_fkey"),
        "FOREIGN KEY (#{quote_name(name)}) REFERENCES",
        "#{quote_name(ref.table)}(#{quote_name(ref.column)})" <>
        reference_on_delete(ref.on_delete),
      ])
    end

    defp column_change({:modify, name, type, opts}) do
      using = Keyword.get(opts, :using, nil)
      assemble(["ALTER COLUMN", quote_name(name), "TYPE", column_type(type, opts), if_do(using, "USING #{using}")])
    end

    defp column_change({:remove, name}), do: "DROP COLUMN #{quote_name(name)}"

    defp column_options(opts) do
      default = Keyword.get(opts, :default)
      null    = Keyword.get(opts, :null)
      pk      = Keyword.get(opts, :primary_key)

      [default_expr(default), null_expr(null), pk_expr(pk)]
    end

    defp pk_expr(true), do: "PRIMARY KEY"
    defp pk_expr(_), do: []

    defp null_expr(false), do: "NOT NULL"
    defp null_expr(true), do: "NULL"
    defp null_expr(_), do: []

    defp default_expr(nil),
      do: []
    defp default_expr(literal) when is_binary(literal),
      do: "DEFAULT '#{escape_string(literal)}'"
    defp default_expr(literal) when is_number(literal) or is_boolean(literal),
      do: "DEFAULT #{literal}"
    defp default_expr({:fragment, expr}),
      do: "DEFAULT #{expr}"

    defp index_expr(literal) when is_binary(literal),
      do: literal
    defp index_expr(literal),
      do: quote_name(literal)

    defp options_expr(nil),
      do: ""
    defp options_expr(keyword) when is_list(keyword),
      do: error!(nil, "PostgreSQL adapter does not support keyword lists in :options")
    defp options_expr(options),
      do: " #{options}"

    defp column_type(%Reference{} = ref, opts),
      do: "#{reference_column_type(ref.type, opts)} REFERENCES " <>
          "#{quote_name(ref.table)}(#{quote_name(ref.column)})" <>
          reference_on_delete(ref.on_delete)

    defp column_type({:array, type}, opts),
      do: column_type(type, opts) <> "[]"
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

    # A reference pointing to a serial column becomes integer in postgres
    defp reference_column_type(:serial, _opts), do: "integer"
    defp reference_column_type(type, opts), do: column_type(type, opts)

    defp reference_on_delete(:nilify_all), do: " ON DELETE SET NULL"
    defp reference_on_delete(:delete_all), do: " ON DELETE CASCADE"
    defp reference_on_delete(_), do: ""

    ## Helpers

    defp quote_name(name)
    defp quote_name(name) when is_atom(name),
      do: quote_name(Atom.to_string(name))
    defp quote_name(name) do
      if String.contains?(name, "\"") do
        error!(nil, "bad field name #{inspect name}")
      end
      <<?", name::binary, ?">>
    end

    defp quote_table(nil, name),    do: quote_table(name)
    defp quote_table(prefix, name), do: quote_table(prefix) <> "." <> quote_table(name)

    defp quote_table(name) when is_atom(name),
      do: quote_table(Atom.to_string(name))
    defp quote_table(name) do
      if String.contains?(name, "\"") do
        error!(nil, "bad table name #{inspect name}")
      end

      # TODO: Remove replace once v0.14.0 is out
      <<?", String.replace(name, ".", "\".\"")::binary, ?">>
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
      :binary.replace(value, "'", "''", [:global])
    end

    defp ecto_to_db({:array, t}), do: ecto_to_db(t) <> "[]"
    defp ecto_to_db(:id),         do: "integer"
    defp ecto_to_db(:binary_id),  do: "uuid"
    defp ecto_to_db(:string),     do: "varchar"
    defp ecto_to_db(:datetime),   do: "timestamp"
    defp ecto_to_db(:binary),     do: "bytea"
    defp ecto_to_db(:map),        do: "jsonb"
    defp ecto_to_db(other),       do: Atom.to_string(other)

    defp error!(nil, message) do
      raise ArgumentError, message
    end
    defp error!(query, message) do
      raise Ecto.QueryError, query: query, message: message
    end
  end
end
