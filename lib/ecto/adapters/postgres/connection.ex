if Code.ensure_loaded?(Postgrex) do

  defmodule Ecto.Adapters.Postgres.Connection do
    @moduledoc false

    @default_port 5432
    @behaviour Ecto.Adapters.SQL.Connection

    ## Module and Options

    def child_spec(opts) do
      json = Application.get_env(:ecto, :json_library)
      extensions = [{Ecto.Adapters.Postgres.DateTime, []},
                    {Postgrex.Extensions.JSON, library: json}]

      opts =
        opts
        |> Keyword.update(:extensions, extensions, &(&1 ++ extensions))
        |> Keyword.update(:port, @default_port, &normalize_port/1)
        |> Keyword.put(:types, true)

      Postgrex.child_spec(opts)
    end

    # TODO: Remove this on 2.1 (normalization should happen on the adapter)
    defp normalize_port(port) when is_binary(port), do: String.to_integer(port)
    defp normalize_port(port) when is_integer(port), do: port

    def to_constraints(%Postgrex.Error{postgres: %{code: :unique_violation, constraint: constraint}}),
      do: [unique: constraint]
    def to_constraints(%Postgrex.Error{postgres: %{code: :foreign_key_violation, constraint: constraint}}),
      do: [foreign_key: constraint]
    def to_constraints(%Postgrex.Error{postgres: %{code: :exclusion_violation, constraint: constraint}}),
      do: [exclude: constraint]
    def to_constraints(%Postgrex.Error{postgres: %{code: :check_violation, constraint: constraint}}),
      do: [check: constraint]

    # Postgres 9.2 and earlier does not provide the constraint field
    def to_constraints(%Postgrex.Error{postgres: %{code: :unique_violation, message: message}}) do
      case :binary.split(message, " unique constraint ") do
        [_, quoted] -> [unique: strip_quotes(quoted)]
        _ -> []
      end
    end
    def to_constraints(%Postgrex.Error{postgres: %{code: :foreign_key_violation, message: message}}) do
      case :binary.split(message, " foreign key constraint ") do
        [_, quoted] -> [foreign_key: strip_quotes(quoted)]
        _ -> []
      end
    end
    def to_constraints(%Postgrex.Error{postgres: %{code: :exclusion_violation, message: message}}) do
      case :binary.split(message, " exclude constraint ") do
        [_, quoted] -> [exclude: strip_quotes(quoted)]
        _ -> []
      end
    end
    def to_constraints(%Postgrex.Error{postgres: %{code: :check_violation, message: message}}) do
      case :binary.split(message, " check constraint ") do
        [_, quoted] -> [check: strip_quotes(quoted)]
        _ -> []
      end
    end

    def to_constraints(%Postgrex.Error{}),
      do: []

    defp strip_quotes(quoted) do
      size = byte_size(quoted) - 2
      <<_, unquoted::binary-size(size), _>> = quoted
      unquoted
    end

    ## Query

    def prepare_execute(conn, name, sql, params, opts) do
      query = %Postgrex.Query{name: name, statement: sql}
      DBConnection.prepare_execute(conn, query, params, opts)
    end

    def execute(conn, sql, params, opts) when is_binary(sql) do
      query = %Postgrex.Query{name: "", statement: sql}
      case DBConnection.prepare_execute(conn, query, params, opts) do
        {:ok, _, query} -> {:ok, query}
        {:error, _} = err -> err
      end
    end

    def execute(conn, %{} = query, params, opts) do
      DBConnection.execute(conn, query, params, opts)
    end

    alias Ecto.Query
    alias Ecto.Query.QueryExpr
    alias Ecto.Query.JoinExpr

    def all(query) do
      sources        = create_names(query)
      distinct_exprs = distinct_exprs(query, sources)

      from     = from(query, sources)
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

    def update_all(%{from: from} = query) do
      sources = create_names(query)
      {from, name} = get_source(query, sources, 0, from)

      fields = update_fields(query, sources)
      {join, wheres} = using_join(query, :update_all, "FROM", sources)
      where = where(%{query | wheres: wheres ++ query.wheres}, sources)

      assemble(["UPDATE #{from} AS #{name} SET", fields, join, where, returning(query, sources)])
    end

    def delete_all(%{from: from} = query) do
      sources = create_names(query)
      {from, name} = get_source(query, sources, 0, from)

      {join, wheres} = using_join(query, :delete_all, "USING", sources)
      where = where(%{query | wheres: wheres ++ query.wheres}, sources)

      assemble(["DELETE FROM #{from} AS #{name}", join, where, returning(query, sources)])
    end

    def insert(prefix, table, header, rows, returning) do
      values =
        if header == [] do
          "VALUES " <> Enum.map_join(rows, ",", fn _ -> "(DEFAULT)" end)
        else
          "(" <> Enum.map_join(header, ",", &quote_name/1) <> ") " <>
          "VALUES " <> insert_all(rows, 1, "")
        end

      assemble(["INSERT INTO #{quote_table(prefix, table)}", values, returning(returning)])
    end

    defp insert_all([row|rows], counter, acc) do
      {counter, row} = insert_each(row, counter, "")
      insert_all(rows, counter, acc <> ",(" <> row <> ")")
    end
    defp insert_all([], _counter, "," <> acc) do
      acc
    end

    defp insert_each([nil|t], counter, acc),
      do: insert_each(t, counter, acc <> ",DEFAULT")
    defp insert_each([_|t], counter, acc),
      do: insert_each(t, counter + 1, acc <> ",$" <> Integer.to_string(counter))
    defp insert_each([], counter, "," <> acc),
      do: {counter, acc}

    def update(prefix, table, fields, filters, returning) do
      {fields, count} = Enum.map_reduce fields, 1, fn field, acc ->
        {"#{quote_name(field)} = $#{acc}", acc + 1}
      end

      {filters, _count} = Enum.map_reduce filters, count, fn field, acc ->
        {"#{quote_name(field)} = $#{acc}", acc + 1}
      end

      assemble(["UPDATE #{quote_table(prefix, table)} SET " <> Enum.join(fields, ", "),
                "WHERE " <> Enum.join(filters, " AND "),
                returning(returning)])
    end

    def delete(prefix, table, filters, returning) do
      {filters, _} = Enum.map_reduce filters, 1, fn field, acc ->
        {"#{quote_name(field)} = $#{acc}", acc + 1}
      end

      assemble(["DELETE FROM #{quote_table(prefix, table)} WHERE " <> Enum.join(filters, " AND "),
                returning(returning)])
    end

    ## Query generation

    binary_ops =
      [==: "=", !=: "!=", <=: "<=", >=: ">=", <:  "<", >:  ">",
       and: "AND", or: "OR", ilike: "ILIKE", like: "LIKE"]

    @binary_ops Keyword.keys(binary_ops)

    Enum.map(binary_ops, fn {op, str} ->
      defp handle_call(unquote(op), 2), do: {:binary_op, unquote(str)}
    end)

    defp handle_call(fun, _arity), do: {:fun, Atom.to_string(fun)}

    defp select(%Query{select: %{fields: fields}, distinct: distinct} = query,
                distinct_exprs, sources) do
      "SELECT " <>
        distinct(distinct, distinct_exprs) <>
        select_fields(fields, sources, query)
    end

    defp select_fields([], _sources, _query),
      do: "TRUE"
    defp select_fields(fields, sources, query),
      do: Enum.map_join(fields, ", ", &expr(&1, sources, query))

    defp distinct_exprs(%Query{distinct: %QueryExpr{expr: exprs}} = query, sources)
        when is_list(exprs) do
      Enum.map_join(exprs, ", ", &expr(&1, sources, query))
    end
    defp distinct_exprs(_, _), do: ""

    defp distinct(nil, _sources), do: ""
    defp distinct(%QueryExpr{expr: true}, _exprs),  do: "DISTINCT "
    defp distinct(%QueryExpr{expr: false}, _exprs), do: ""
    defp distinct(_query, exprs), do: "DISTINCT ON (" <> exprs <> ") "

    defp from(%{from: from} = query, sources) do
      {from, name} = get_source(query, sources, 0, from)
      "FROM #{from} AS #{name}"
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

    defp using_join(%Query{joins: []}, _kind, _prefix, _sources), do: {[], []}
    defp using_join(%Query{joins: joins} = query, kind, prefix, sources) do
      froms =
        Enum.map_join(joins, ", ", fn
          %JoinExpr{qual: :inner, ix: ix, source: source} ->
            {join, name} = get_source(query, sources, ix, source)
            join <> " AS " <> name
          %JoinExpr{qual: qual} ->
            error!(query, "PostgreSQL supports only inner joins on #{kind}, got: `#{qual}`")
        end)

      wheres =
        for %JoinExpr{on: %QueryExpr{expr: value} = expr} <- joins,
            value != true,
            do: expr

      {prefix <> " " <> froms, wheres}
    end

    defp join(%Query{joins: []}, _sources), do: []
    defp join(%Query{joins: joins} = query, sources) do
      Enum.map_join(joins, " ", fn
        %JoinExpr{on: %QueryExpr{expr: expr}, qual: qual, ix: ix, source: source} ->
          {join, name} = get_source(query, sources, ix, source)
          qual = join_qual(qual)
          qual <> " " <> join <> " AS " <> name <> " ON " <> expr(expr, sources, query)
      end)
    end

    defp join_qual(:inner), do: "INNER JOIN"
    defp join_qual(:inner_lateral), do: "INNER JOIN LATERAL"
    defp join_qual(:left),  do: "LEFT OUTER JOIN"
    defp join_qual(:left_lateral),  do: "LEFT OUTER JOIN LATERAL"
    defp join_qual(:right), do: "RIGHT OUTER JOIN"
    defp join_qual(:full),  do: "FULL OUTER JOIN"

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

    defp expr({:&, _, [idx, fields, _counter]}, sources, query) do
      {_, name, schema} = elem(sources, idx)
      if is_nil(schema) and is_nil(fields) do
        error!(query, "PostgreSQL requires a schema module when using selector " <>
          "#{inspect name} but none was given. " <>
          "Please specify a schema or specify exactly which fields from " <>
          "#{inspect name} you desire")
      end
      Enum.map_join(fields, ", ", &"#{name}.#{quote_name(&1)}")
    end

    defp expr({:in, _, [_left, []]}, _sources, _query) do
      "false"
    end

    defp expr({:in, _, [left, right]}, sources, query) when is_list(right) do
      args = Enum.map_join right, ",", &expr(&1, sources, query)
      expr(left, sources, query) <> " IN (" <> args <> ")"
    end

    defp expr({:in, _, [left, {:^, _, [ix, _]}]}, sources, query) do
      expr(left, sources, query) <> " = ANY($#{ix+1})"
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

    defp expr(%Ecto.SubQuery{query: query}, _sources, _query) do
      all(query)
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
      {modifier, args} =
        case args do
         [rest, :distinct] -> {"DISTINCT ", [rest]}
         _ -> {"", args}
       end

      case handle_call(fun, length(args)) do
        {:binary_op, op} ->
          [left, right] = args
          op_to_binary(left, sources, query) <>
          " #{op} "
          <> op_to_binary(right, sources, query)

        {:fun, fun} ->
          "#{fun}(" <> modifier <> Enum.map_join(args, ", ", &expr(&1, sources, query)) <> ")"
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

    defp returning(%Query{select: nil}, _sources),
      do: []
    defp returning(%Query{select: %{fields: fields}} = query, sources),
      do: "RETURNING " <> select_fields(fields, sources, query)

    defp returning([]),
      do: []
    defp returning(returning),
      do: "RETURNING " <> Enum.map_join(returning, ", ", &quote_name/1)

    defp create_names(%{prefix: prefix, sources: sources}) do
      create_names(prefix, sources, 0, tuple_size(sources)) |> List.to_tuple()
    end

    defp create_names(prefix, sources, pos, limit) when pos < limit do
      current =
        case elem(sources, pos) do
          {table, schema} ->
            name = String.first(table) <> Integer.to_string(pos)
            {quote_table(prefix, table), name, schema}
          {:fragment, _, _} ->
            {nil, "f" <> Integer.to_string(pos), nil}
          %Ecto.SubQuery{} ->
            {nil, "s" <> Integer.to_string(pos), nil}
        end
      [current|create_names(prefix, sources, pos + 1, limit)]
    end

    defp create_names(_prefix, _sources, pos, pos) do
      []
    end

    # DDL

    alias Ecto.Migration.{Table, Index, Reference, Constraint}

    @drops [:drop, :drop_if_exists]

    def execute_ddl({command, %Table{}=table, columns}) when command in [:create, :create_if_not_exists] do
      options       = options_expr(table.options)
      if_not_exists = if command == :create_if_not_exists, do: " IF NOT EXISTS", else: ""
      pk_definition = case pk_definition(columns) do
        nil -> ""
        pk -> ", #{pk}"
      end

      "CREATE TABLE" <> if_not_exists <>
        " #{quote_table(table.prefix, table.name)}" <>
        " (#{column_definitions(table, columns)}#{pk_definition})" <> options <>
        comment_on(:table, table.name, table.comment) <> comments_for_columns(table, columns)
    end

    def execute_ddl({command, %Table{}=table}) when command in @drops do
      if_exists = if command == :drop_if_exists, do: " IF EXISTS", else: ""

      "DROP TABLE" <> if_exists <> " #{quote_table(table.prefix, table.name)}"
    end

    def execute_ddl({:alter, %Table{}=table, changes}) do
      pk_definition = case pk_definition(changes) do
        nil -> ""
        pk -> ", ADD #{pk}"
      end
      "ALTER TABLE #{quote_table(table.prefix, table.name)} #{column_changes(table, changes)}" <>
      "#{pk_definition}" <> comment_on(:table, table.name, table.comment) <>
      comments_for_columns(table, changes)
    end

    def execute_ddl({:create, %Index{}=index}) do
      fields = Enum.map_join(index.columns, ", ", &index_expr/1)

      assemble(["CREATE",
                if_do(index.unique, "UNIQUE"),
                "INDEX",
                if_do(index.concurrently, "CONCURRENTLY"),
                quote_name(index.name),
                "ON",
                quote_table(index.prefix, index.table),
                if_do(index.using, "USING #{index.using}"),
                "(#{fields})",
                if_do(index.where, "WHERE #{index.where}"),
                if_do(index.comment, comment_on(:index, index.name, index.comment))])
    end

    def execute_ddl({:create_if_not_exists, %Index{}=index}) do
      assemble(["DO $$",
                "BEGIN",
                execute_ddl({:create, index}) <> ";",
                "EXCEPTION WHEN duplicate_table THEN END; $$;"])
    end

    def execute_ddl({command, %Index{}=index}) when command in @drops do
      if_exists = if command == :drop_if_exists, do: "IF EXISTS", else: []

      assemble(["DROP",
                "INDEX",
                if_do(index.concurrently, "CONCURRENTLY"),
                if_exists,
                quote_table(index.prefix, index.name)])
    end

    def execute_ddl({:rename, %Table{}=current_table, %Table{}=new_table}) do
      "ALTER TABLE #{quote_table(current_table.prefix, current_table.name)} RENAME TO #{quote_table(new_table.prefix, new_table.name)}"
    end

    def execute_ddl({:rename, %Table{}=table, current_column, new_column}) do
      "ALTER TABLE #{quote_table(table.prefix, table.name)} RENAME #{quote_name(current_column)} TO #{quote_name(new_column)}"
    end

    def execute_ddl({:create, %Constraint{}=constraint}) do
      "ALTER TABLE #{quote_table(constraint.prefix, constraint.table)} ADD #{new_constraint_expr(constraint)}" <>
      comment_on(:constraint, constraint.name, constraint.comment)
    end

    def execute_ddl({:drop, %Constraint{}=constraint}) do
      "ALTER TABLE #{quote_table(constraint.prefix, constraint.table)} DROP CONSTRAINT #{quote_name(constraint.name)}"
    end

    def execute_ddl(string) when is_binary(string), do: string

    def execute_ddl(keyword) when is_list(keyword),
      do: error!(nil, "PostgreSQL adapter does not support keyword lists in execute")

    defp pk_definition(columns) do
      pks =
        for {_, name, _, opts} <- columns,
            opts[:primary_key],
            do: name

      case pks do
        [] -> nil
        _  -> "PRIMARY KEY (" <> Enum.map_join(pks, ", ", &quote_name/1) <> ")"
      end
    end

    defp comment_on(_database_object, _name, nil), do:  ""
    defp comment_on(:column, {table_name, column_name}, comment) do
      column_name = quote_table(table_name, column_name)
      "; COMMENT ON COLUMN #{column_name} IS #{single_quote(comment)}"
    end

    defp comment_on(:table, name, comment) do
      "; COMMENT ON TABLE #{quote_name(name)} IS #{single_quote(comment)}"
    end

    defp comment_on(:constraint, name, comment) do
      "; COMMENT ON CONSTRAINT #{quote_name(name)} IS #{single_quote(comment)}"
    end

    defp comment_on(:index, name, comment) do
      "; COMMENT ON INDEX #{quote_name(name)} IS #{single_quote(comment)}"
    end

    defp comments_for_columns(table, columns) do
      Enum.map_join(columns, "", fn
        {_operation, column_name, _column_type, opts} ->
          comment_on(:column, {table.name, column_name}, opts[:comment])
        _ -> ""
      end)
    end

    defp column_definitions(table, columns) do
      Enum.map_join(columns, ", ", &column_definition(table, &1))
    end

    defp column_definition(table, {:add, name, %Reference{} = ref, opts}) do
      assemble([
        quote_name(name), reference_column_type(ref.type, opts),
        column_options(ref.type, opts), reference_expr(ref, table, name)
      ])
    end

    defp column_definition(_table, {:add, name, type, opts}) do
      assemble([quote_name(name), column_type(type, opts), column_options(type, opts)])
    end

    defp column_changes(table, columns) do
      Enum.map_join(columns, ", ", &column_change(table, &1))
    end

    defp column_change(table, {:add, name, %Reference{} = ref, opts}) do
      assemble([
        "ADD COLUMN", quote_name(name), reference_column_type(ref.type, opts),
        column_options(ref.type, opts), reference_expr(ref, table, name)
      ])
    end

    defp column_change(_table, {:add, name, type, opts}) do
      assemble(["ADD COLUMN", quote_name(name), column_type(type, opts), column_options(type, opts)])
    end

    defp column_change(table, {:modify, name, %Reference{} = ref, opts}) do
      assemble([
        "ALTER COLUMN", quote_name(name), "TYPE", reference_column_type(ref.type, opts),
        constraint_expr(ref, table, name), modify_null(name, opts), modify_default(name, ref.type, opts)
      ])
    end

    defp column_change(_table, {:modify, name, type, opts}) do
      assemble(["ALTER COLUMN", quote_name(name), "TYPE",
                column_type(type, opts), modify_null(name, opts), modify_default(name, type, opts)])
    end

    defp column_change(_table, {:remove, name}), do: "DROP COLUMN #{quote_name(name)}"

    defp modify_null(name, opts) do
      case Keyword.get(opts, :null) do
        true  -> ", ALTER COLUMN #{quote_name(name)} DROP NOT NULL"
        false -> ", ALTER COLUMN #{quote_name(name)} SET NOT NULL"
        nil   -> []
      end
    end

    defp modify_default(name, type, opts) do
      case Keyword.fetch(opts, :default) do
        {:ok, val} -> ", ALTER COLUMN #{quote_name(name)} SET #{default_expr({:ok, val}, type)}"
        :error -> []
      end
    end

    defp column_options(type, opts) do
      default = Keyword.fetch(opts, :default)
      null    = Keyword.get(opts, :null)
      [default_expr(default, type), null_expr(null)]
    end

    defp null_expr(false), do: "NOT NULL"
    defp null_expr(true), do: "NULL"
    defp null_expr(_), do: []

    defp new_constraint_expr(%Constraint{check: check} = constraint) when is_binary(check) do
      "CONSTRAINT #{quote_name(constraint.name)} CHECK (#{check})"
    end
    defp new_constraint_expr(%Constraint{exclude: exclude} = constraint) when is_binary(exclude) do
      "CONSTRAINT #{quote_name(constraint.name)} EXCLUDE USING #{exclude}"
    end

    defp default_expr({:ok, nil}, _type),
      do: "DEFAULT NULL"
    defp default_expr({:ok, []}, type),
      do: "DEFAULT ARRAY[]::#{ecto_to_db(type)}"
    defp default_expr({:ok, literal}, _type) when is_binary(literal),
      do: "DEFAULT '#{escape_string(literal)}'"
    defp default_expr({:ok, literal}, _type) when is_number(literal) or is_boolean(literal),
      do: "DEFAULT #{literal}"
    defp default_expr({:ok, {:fragment, expr}}, _type),
      do: "DEFAULT #{expr}"
    defp default_expr({:ok, expr}, type),
      do: raise(ArgumentError, "unknown default `#{inspect expr}` for type `#{inspect type}`. " <>
                               ":default may be a string, number, boolean, empty list or a fragment(...)")
    defp default_expr(:error, _),
      do: []

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

    defp reference_expr(%Reference{} = ref, table, name),
      do: "CONSTRAINT #{reference_name(ref, table, name)} REFERENCES " <>
          "#{quote_table(table.prefix, ref.table)}(#{quote_name(ref.column)})" <>
          reference_on_delete(ref.on_delete) <> reference_on_update(ref.on_update)

    defp constraint_expr(%Reference{} = ref, table, name),
      do: ", ADD CONSTRAINT #{reference_name(ref, table, name)} " <>
          "FOREIGN KEY (#{quote_name(name)}) " <>
          "REFERENCES #{quote_table(table.prefix, ref.table)}(#{quote_name(ref.column)})" <>
          reference_on_delete(ref.on_delete) <> reference_on_update(ref.on_update)

    # A reference pointing to a serial column becomes integer in postgres
    defp reference_name(%Reference{name: nil}, table, column),
      do: quote_name("#{table.name}_#{column}_fkey")
    defp reference_name(%Reference{name: name}, _table, _column),
      do: quote_name(name)

    defp reference_column_type(:serial, _opts), do: "integer"
    defp reference_column_type(type, opts), do: column_type(type, opts)

    defp reference_on_delete(:nilify_all), do: " ON DELETE SET NULL"
    defp reference_on_delete(:delete_all), do: " ON DELETE CASCADE"
    defp reference_on_delete(_), do: ""

    defp reference_on_update(:nilify_all), do: " ON UPDATE SET NULL"
    defp reference_on_update(:update_all), do: " ON UPDATE CASCADE"
    defp reference_on_update(_), do: ""

    ## Helpers

    defp get_source(query, sources, ix, source) do
      {expr, name, _schema} = elem(sources, ix)
      {expr || "(" <> expr(source, sources, query) <> ")", name}
    end

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
      <<?", name::binary, ?">>
    end

    defp single_quote(value), do: "\'#{escape_string(value)}\'"

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
    defp ecto_to_db({:map, _}),   do: "jsonb"
    defp ecto_to_db(other),       do: Atom.to_string(other)

    defp error!(nil, message) do
      raise ArgumentError, message
    end
    defp error!(query, message) do
      raise Ecto.QueryError, query: query, message: message
    end
  end
end
