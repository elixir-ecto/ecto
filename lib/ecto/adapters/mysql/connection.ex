if Code.ensure_loaded?(Mariaex) do

  defmodule Ecto.Adapters.MySQL.Connection do
    @moduledoc false
    @behaviour Ecto.Adapters.SQL.Connection

    ## Connection

    def child_spec(opts) do
      Mariaex.child_spec(opts)
    end

    ## Query

    def prepare_execute(conn, name, sql, params, opts) do
      query = %Mariaex.Query{name: name, statement: sql}
      DBConnection.prepare_execute(conn, query, map_params(params), opts)
    end

    def execute(conn, sql, params, opts) when is_binary(sql) or is_list(sql) do
      query = %Mariaex.Query{name: "", statement: sql}
      case DBConnection.prepare_execute(conn, query, map_params(params), opts) do
        {:ok, _, query} -> {:ok, query}
        {:error, _} = err -> err
      end
    end

    def execute(conn, %{} = query, params, opts) do
      DBConnection.execute(conn, query, map_params(params), opts)
    end

    def stream(conn, sql, params, opts) do
      Mariaex.stream(conn, sql, params, opts)
    end

    defp map_params(params) do
      Enum.map params, fn
        %{__struct__: _} = value ->
          value
        %{} = value ->
          Ecto.Adapter.json_library().encode!(value)
        value ->
          value
      end
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

    ## Query

    alias Ecto.Query
    alias Ecto.Query.{BooleanExpr, JoinExpr, QueryExpr}

    def all(query) do
      sources = create_names(query)

      from     = from(query, sources)
      select   = select(query, sources)
      join     = join(query, sources)
      where    = where(query, sources)
      group_by = group_by(query, sources)
      having   = having(query, sources)
      order_by = order_by(query, sources)
      limit    = limit(query, sources)
      offset   = offset(query, sources)
      lock     = lock(query.lock)

      [select, from, join, where, group_by, having, order_by, limit, offset | lock]
    end

    def update_all(query, prefix \\ nil)

    def update_all(%{from: from, select: nil} = query, prefix) do
      sources = create_names(query)
      {from, name} = get_source(query, sources, 0, from)

      fields = if prefix do
        update_fields(:on_conflict, query, sources)
      else
        update_fields(:update, query, sources)
      end

      {join, wheres} = using_join(query, :update_all, sources)
      prefix = prefix || ["UPDATE ", from, " AS ", name, join, " SET "]
      where  = where(%{query | wheres: wheres ++ query.wheres}, sources)

      [prefix, fields | where]
    end
    def update_all(_query, _prefix) do
      error!(nil, "RETURNING is not supported in update_all by MySQL")
    end

    def delete_all(%{select: nil} = query) do
      sources = create_names(query)
      {_, name, _} = elem(sources, 0)

      from   = from(query, sources)
      join   = join(query, sources)
      where  = where(query, sources)

      ["DELETE ", name, ".*", from, join | where]
    end
    def delete_all(_query),
      do: error!(nil, "RETURNING is not supported in delete_all by MySQL")

    def insert(prefix, table, header, rows, on_conflict, []) do
      fields = intersperse_map(header, ?,, &quote_name/1)
      ["INSERT INTO ", quote_table(prefix, table), " (", fields, ") VALUES ",
       insert_all(rows) | on_conflict(on_conflict, header)]
    end
    def insert(_prefix, _table, _header, _rows, _on_conflict, _returning) do
      error!(nil, "RETURNING is not supported in insert/insert_all by MySQL")
    end

    defp on_conflict({_, _, [_ | _]}, _header) do
      error!(nil, "The :conflict_target option is not supported in insert/insert_all by MySQL")
    end
    defp on_conflict({:raise, _, []}, _header) do
      []
    end
    defp on_conflict({:nothing, _, []}, [field | _]) do
      quoted = quote_name(field)
      [" ON DUPLICATE KEY UPDATE ", quoted, " = " | quoted]
    end
    defp on_conflict({:replace_all, _, []}, header) do
      [" ON DUPLICATE KEY UPDATE " |
       intersperse_map(header, ?,, fn field ->
         quoted = quote_name(field)
         [quoted, " = VALUES(", quoted, ?)]
       end)]
    end
    defp on_conflict({%{wheres: []} = query, _, []}, _header) do
      [" ON DUPLICATE KEY " | update_all(query, "UPDATE ")]
    end
    defp on_conflict({_query, _, []}, _header) do
      error!(nil, "Using a query with :where in combination with the :on_conflict option is not supported by MySQL")
    end

    defp insert_all(rows) do
      intersperse_map(rows, ?,, fn row ->
        [?(, intersperse_map(row, ?,, &insert_all_value/1), ?)]
      end)
    end

    defp insert_all_value(nil), do: "DEFAULT"
    defp insert_all_value(_),   do: '?'

    def update(prefix, table, fields, filters, _returning) do
      fields = intersperse_map(fields, ", ", &[quote_name(&1), " = ?"])
      filters = intersperse_map(filters, " AND ", &[quote_name(&1), " = ?"])
      ["UPDATE ", quote_table(prefix, table), " SET ", fields, " WHERE " | filters]
    end

    def delete(prefix, table, filters, _returning) do
      filters = intersperse_map(filters, " AND ", &[quote_name(&1), " = ?"])
      ["DELETE FROM ", quote_table(prefix, table), " WHERE " | filters]
    end

    ## Query generation

    binary_ops =
      [==: " = ", !=: " != ", <=: " <= ", >=: " >= ", <: " < ", >: " > ",
       and: " AND ", or: " OR ", like: " LIKE "]

    @binary_ops Keyword.keys(binary_ops)

    Enum.map(binary_ops, fn {op, str} ->
      defp handle_call(unquote(op), 2), do: {:binary_op, unquote(str)}
    end)

    defp handle_call(fun, _arity), do: {:fun, Atom.to_string(fun)}

    defp select(%Query{select: %{fields: fields}, distinct: distinct} = query,
                sources) do
      ["SELECT ", distinct(distinct, sources, query) | select(fields, sources, query)]
    end

    defp distinct(nil, _sources, _query), do: []
    defp distinct(%QueryExpr{expr: true}, _sources, _query),  do: "DISTINCT "
    defp distinct(%QueryExpr{expr: false}, _sources, _query), do: []
    defp distinct(%QueryExpr{expr: exprs}, _sources, query) when is_list(exprs) do
      error!(query, "DISTINCT with multiple columns is not supported by MySQL")
    end

    defp select([], _sources, _query),
      do: "TRUE"
    defp select(fields, sources, query) do
      intersperse_map(fields, ", ", fn
        {key, value} ->
          [expr(value, sources, query), " AS ", quote_name(key)]
        value ->
          expr(value, sources, query)
      end)
    end

    defp from(%{from: from} = query, sources) do
      {from, name} = get_source(query, sources, 0, from)
      [" FROM ", from, " AS " | name]
    end

    defp update_fields(type, %Query{updates: updates} = query, sources) do
     fields = for(%{expr: expr} <- updates,
                   {op, kw} <- expr,
                   {key, value} <- kw,
                   do: update_op(op, update_key(type, key, query, sources), value, sources, query))
      Enum.intersperse(fields, ", ")
    end

    defp update_key(:update, key, %Query{from: from} = query, sources) do
      {_from, name} = get_source(query, sources, 0, from)

      [name, ?. | quote_name(key)]
    end
    defp update_key(:on_conflict, key, _query, _sources) do
      quote_name(key)
    end

    defp update_op(:set, quoted_key, value, sources, query) do
      [quoted_key, " = " | expr(value, sources, query)]
    end

    defp update_op(:inc, quoted_key, value, sources, query) do
      [quoted_key, " = ", quoted_key, " + " | expr(value, sources, query)]
    end

    defp update_op(command, _quoted_key, _value, _sources, query) do
      error!(query, "Unknown update operation #{inspect command} for MySQL")
    end

    defp using_join(%Query{joins: []}, _kind, _sources), do: {[], []}
    defp using_join(%Query{joins: joins} = query, kind, sources) do
      froms =
        intersperse_map(joins, ", ", fn
          %JoinExpr{qual: :inner, ix: ix, source: source} ->
            {join, name} = get_source(query, sources, ix, source)
            [join, " AS " | name]
          %JoinExpr{qual: qual} ->
            error!(query, "MySQL adapter supports only inner joins on #{kind}, got: `#{qual}`")
        end)

      wheres =
        for %JoinExpr{on: %QueryExpr{expr: value} = expr} <- joins,
            value != true,
            do: expr |> Map.put(:__struct__, BooleanExpr) |> Map.put(:op, :and)

      {[?,, ?\s | froms], wheres}
    end

    defp join(%Query{joins: []}, _sources), do: []
    defp join(%Query{joins: joins} = query, sources) do
      Enum.map(joins, fn
        %JoinExpr{on: %QueryExpr{expr: expr}, qual: qual, ix: ix, source: source} ->
          {join, name} = get_source(query, sources, ix, source)
          [join_qual(qual, query), join, " AS ", name | join_on(qual, expr, sources, query)]
      end)
    end

    defp join_on(:cross, true, _sources, _query), do: []
    defp join_on(_qual, expr, sources, query), do: [" ON " | expr(expr, sources, query)]

    defp join_qual(:inner, _), do: " INNER JOIN "
    defp join_qual(:left, _),  do: " LEFT OUTER JOIN "
    defp join_qual(:right, _), do: " RIGHT OUTER JOIN "
    defp join_qual(:full, _),  do: " FULL OUTER JOIN "
    defp join_qual(:cross, _), do: " CROSS JOIN "
    defp join_qual(mode, q),   do: error!(q, "join `#{inspect mode}` not supported by MySQL")

    defp where(%Query{wheres: wheres} = query, sources) do
      boolean(" WHERE ", wheres, sources, query)
    end

    defp having(%Query{havings: havings} = query, sources) do
      boolean(" HAVING ", havings, sources, query)
    end

    defp group_by(%Query{group_bys: []}, _sources), do: []
    defp group_by(%Query{group_bys: group_bys} = query, sources) do
      [" GROUP BY " |
       intersperse_map(group_bys, ", ", fn
         %QueryExpr{expr: expr} ->
           intersperse_map(expr, ", ", &expr(&1, sources, query))
       end)]
    end

    defp order_by(%Query{order_bys: []}, _sources), do: []
    defp order_by(%Query{order_bys: order_bys} = query, sources) do
      [" ORDER BY " |
       intersperse_map(order_bys, ", ", fn
         %QueryExpr{expr: expr} ->
           intersperse_map(expr, ", ", &order_by_expr(&1, sources, query))
       end)]
    end

    defp order_by_expr({dir, expr}, sources, query) do
      str = expr(expr, sources, query)
      case dir do
        :asc  -> str
        :desc -> [str | " DESC"]
      end
    end

    defp limit(%Query{limit: nil}, _sources), do: []
    defp limit(%Query{limit: %QueryExpr{expr: expr}} = query, sources) do
      [" LIMIT " | expr(expr, sources, query)]
    end

    defp offset(%Query{offset: nil}, _sources), do: []
    defp offset(%Query{offset: %QueryExpr{expr: expr}} = query, sources) do
      [" OFFSET " | expr(expr, sources, query)]
    end

    defp lock(nil), do: []
    defp lock(lock_clause), do: [?\s | lock_clause]

    defp boolean(_name, [], _sources, _query), do: []
    defp boolean(name, [%{expr: expr, op: op} | query_exprs], sources, query) do
      [name,
       Enum.reduce(query_exprs, {op, paren_expr(expr, sources, query)}, fn
         %BooleanExpr{expr: expr, op: op}, {op, acc} ->
           {op, [acc, operator_to_boolean(op) | paren_expr(expr, sources, query)]}
         %BooleanExpr{expr: expr, op: op}, {_, acc} ->
           {op, [?(, acc, ?), operator_to_boolean(op) | paren_expr(expr, sources, query)]}
       end) |> elem(1)]
    end

    defp operator_to_boolean(:and), do: " AND "
    defp operator_to_boolean(:or), do: " OR "

    defp paren_expr(expr, sources, query) do
      [?(, expr(expr, sources, query), ?)]
    end

    defp expr({:^, [], [_ix]}, _sources, _query) do
      '?'
    end

    defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources, _query)
        when is_atom(field) do
      {_, name, _} = elem(sources, idx)
      [name, ?. | quote_name(field)]
    end

    defp expr({:&, _, [idx]}, sources, query) do
      {source, _name, _schema} = elem(sources, idx)
      error!(query, "MySQL does not support selecting all fields from #{source} without a schema. " <>
                    "Please specify a schema or specify exactly which fields you want to select")
    end

    defp expr({:in, _, [_left, []]}, _sources, _query) do
      "false"
    end

    defp expr({:in, _, [left, right]}, sources, query) when is_list(right) do
      args = intersperse_map(right, ?,, &expr(&1, sources, query))
      [expr(left, sources, query), " IN (", args, ?)]
    end

    defp expr({:in, _, [_, {:^, _, [_, 0]}]}, _sources, _query) do
      "false"
    end

    defp expr({:in, _, [left, {:^, _, [_, length]}]}, sources, query) do
      args = Enum.intersperse(List.duplicate(??, length), ?,)
      [expr(left, sources, query), " IN (", args, ?)]
    end

    defp expr({:in, _, [left, right]}, sources, query) do
      [expr(left, sources, query), " = ANY(", expr(right, sources, query), ?)]
    end

    defp expr({:is_nil, _, [arg]}, sources, query) do
      [expr(arg, sources, query) | " IS NULL"]
    end

    defp expr({:not, _, [expr]}, sources, query) do
      ["NOT (", expr(expr, sources, query), ?)]
    end

    defp expr(%Ecto.SubQuery{query: query}, _sources, _query) do
      all(query)
    end

    defp expr({:fragment, _, [kw]}, _sources, query) when is_list(kw) or tuple_size(kw) == 3 do
      error!(query, "MySQL adapter does not support keyword or interpolated fragments")
    end

    defp expr({:fragment, _, parts}, sources, query) do
      Enum.map(parts, fn
        {:raw, part}  -> part
        {:expr, expr} -> expr(expr, sources, query)
      end)
    end

    defp expr({:datetime_add, _, [datetime, count, interval]}, sources, query) do
      ["CAST(date_add(", expr(datetime, sources, query), ", ",
       interval(count, interval, sources, query) | ") AS datetime)"]
    end

    defp expr({:date_add, _, [date, count, interval]}, sources, query) do
      ["CAST(date_add(", expr(date, sources, query), ", ",
       interval(count, interval, sources, query) | ") AS date)"]
    end

    defp expr({:ilike, _, [_, _]}, _sources, query) do
      error!(query, "ilike is not supported by MySQL")
    end

    defp expr({fun, _, args}, sources, query) when is_atom(fun) and is_list(args) do
      {modifier, args} =
        case args do
          [rest, :distinct] -> {"DISTINCT ", [rest]}
          _ -> {[], args}
        end

      case handle_call(fun, length(args)) do
        {:binary_op, op} ->
          [left, right] = args
          [op_to_binary(left, sources, query), op | op_to_binary(right, sources, query)]
        {:fun, fun} ->
          [fun, ?(, modifier, intersperse_map(args, ", ", &expr(&1, sources, query)), ?)]
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
      [?x, ?', hex, ?']
    end

    defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources, query)
         when type in [:decimal, :float] do
      [expr(other, sources, query), " + 0"]
    end

    defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources, query) do
      ["CAST(", expr(other, sources, query), " AS ", ecto_cast_to_db(type, query), ?)]
    end

    defp expr(nil, _sources, _query),   do: "NULL"
    defp expr(true, _sources, _query),  do: "TRUE"
    defp expr(false, _sources, _query), do: "FALSE"

    defp expr(literal, _sources, _query) when is_binary(literal) do
      [?', escape_string(literal), ?']
    end

    defp expr(literal, _sources, _query) when is_integer(literal) do
      Integer.to_string(literal)
    end

    defp expr(literal, _sources, _query) when is_float(literal) do
      # MySQL doesn't support float cast
      ["(0 + ", Float.to_string(literal), ?)]
    end

    defp interval(count, "millisecond", sources, query) do
      ["INTERVAL (", expr(count, sources, query) | " * 1000) microsecond"]
    end

    defp interval(count, interval, sources, query) do
      ["INTERVAL ", expr(count, sources, query), ?\s | interval]
    end

    defp op_to_binary({op, _, [_, _]} = expr, sources, query) when op in @binary_ops do
      paren_expr(expr, sources, query)
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
          {table, schema} ->
            name = [create_alias(table) | Integer.to_string(pos)]
            {quote_table(prefix, table), name, schema}
          {:fragment, _, _} ->
            {nil, [?f | Integer.to_string(pos)], nil}
          %Ecto.SubQuery{} ->
            {nil, [?s | Integer.to_string(pos)], nil}
        end
      [current | create_names(prefix, sources, pos + 1, limit)]
    end

    defp create_names(_prefix, _sources, pos, pos) do
      []
    end

    defp create_alias(<<first, _rest::binary>>) when first in ?a..?z when first in ?A..?Z do
      <<first>>
    end
    defp create_alias(_) do
      "t"
    end

    ## DDL

    alias Ecto.Migration.{Table, Index, Reference, Constraint}

    def execute_ddl({command, %Table{} = table, columns}) when command in [:create, :create_if_not_exists] do
      table_structure =
        case column_definitions(table, columns) ++ pk_definitions(columns, ", ") do
          [] -> []
          list -> [?\s, ?(, list, ?)]
        end

      [["CREATE TABLE ",
        if_do(command == :create_if_not_exists, "IF NOT EXISTS "),
        quote_table(table.prefix, table.name),
        table_structure,
        engine_expr(table.engine), options_expr(table.options)]]
    end

    def execute_ddl({command, %Table{} = table}) when command in [:drop, :drop_if_exists] do
      [["DROP TABLE ", if_do(command == :drop_if_exists, "IF EXISTS "),
        quote_table(table.prefix, table.name)]]
    end

    def execute_ddl({:alter, %Table{} = table, changes}) do
      [["ALTER TABLE ", quote_table(table.prefix, table.name), ?\s,
        column_changes(table, changes), pk_definitions(changes, ", ADD ")]]
    end

    def execute_ddl({:create, %Index{} = index}) do
      if index.where do
        error!(nil, "MySQL adapter does not support where in indexes")
      end

      [["CREATE", if_do(index.unique, " UNIQUE"), " INDEX ",
        quote_name(index.name),
        " ON ",
        quote_table(index.prefix, index.table), ?\s,
        ?(, intersperse_map(index.columns, ", ", &index_expr/1), ?),
        if_do(index.using, [" USING ", to_string(index.using)]),
        if_do(index.concurrently, " LOCK=NONE")]]
    end

    def execute_ddl({:create_if_not_exists, %Index{}}),
      do: error!(nil, "MySQL adapter does not support create if not exists for index")

    def execute_ddl({:create, %Constraint{check: check}}) when is_binary(check),
      do: error!(nil, "MySQL adapter does not support check constraints")
    def execute_ddl({:create, %Constraint{exclude: exclude}}) when is_binary(exclude),
      do: error!(nil, "MySQL adapter does not support exclusion constraints")

    def execute_ddl({:drop, %Index{} = index}) do
      [["DROP INDEX ",
        quote_name(index.name),
        " ON ", quote_table(index.prefix, index.table),
        if_do(index.concurrently, " LOCK=NONE")]]
    end

    def execute_ddl({:drop, %Constraint{}}),
      do: error!(nil, "MySQL adapter does not support constraints")

    def execute_ddl({:drop_if_exists, %Index{}}),
      do: error!(nil, "MySQL adapter does not support drop if exists for index")

    def execute_ddl({:rename, %Table{} = current_table, %Table{} = new_table}) do
      [["RENAME TABLE ", quote_table(current_table.prefix, current_table.name),
        " TO ", quote_table(new_table.prefix, new_table.name)]]
    end

    def execute_ddl({:rename, _table, _current_column, _new_column}) do
      error!(nil, "MySQL adapter does not support renaming columns")
    end

    def execute_ddl(string) when is_binary(string), do: [string]

    def execute_ddl(keyword) when is_list(keyword),
      do: error!(nil, "MySQL adapter does not support keyword lists in execute")

    defp pk_definitions(columns, prefix) do
      pks =
        for {_, name, _, opts} <- columns,
            opts[:primary_key],
            do: name

      case pks do
        [] -> []
        _  -> [[prefix, "PRIMARY KEY (", intersperse_map(pks, ", ", &quote_name/1), ?)]]
      end
    end

    defp column_definitions(table, columns) do
      intersperse_map(columns, ", ", &column_definition(table, &1))
    end

    defp column_definition(table, {:add, name, %Reference{} = ref, opts}) do
      [quote_name(name), ?\s, reference_column_type(ref.type, opts),
       column_options(opts), reference_expr(ref, table, name)]
    end

    defp column_definition(_table, {:add, name, type, opts}) do
      [quote_name(name), ?\s, column_type(type, opts), column_options(opts)]
    end

    defp column_changes(table, columns) do
      intersperse_map(columns, ", ", &column_change(table, &1))
    end

    defp column_change(table, {:add, name, %Reference{} = ref, opts}) do
      ["ADD ", quote_name(name), ?\s, reference_column_type(ref.type, opts),
       column_options(opts), constraint_expr(ref, table, name)]
    end

    defp column_change(_table, {:add, name, type, opts}) do
      ["ADD ", quote_name(name), ?\s, column_type(type, opts), column_options(opts)]
    end

    defp column_change(table, {:modify, name, %Reference{} = ref, opts}) do
      ["MODIFY ", quote_name(name), ?\s, reference_column_type(ref.type, opts),
       column_options(opts), constraint_expr(ref, table, name)]
    end

    defp column_change(_table, {:modify, name, type, opts}) do
      ["MODIFY ", quote_name(name), ?\s, column_type(type, opts), column_options(opts)]
    end

    defp column_change(_table, {:remove, name}), do: ["DROP ", quote_name(name)]

    defp column_options(opts) do
      default = Keyword.fetch(opts, :default)
      null    = Keyword.get(opts, :null)
      [default_expr(default), null_expr(null)]
    end

    defp null_expr(false), do: " NOT NULL"
    defp null_expr(true), do: " NULL"
    defp null_expr(_), do: []

    defp default_expr({:ok, nil}),
      do: " DEFAULT NULL"
    defp default_expr({:ok, literal}) when is_binary(literal),
      do: [" DEFAULT '", escape_string(literal), ?']
    defp default_expr({:ok, literal}) when is_number(literal) or is_boolean(literal),
      do: [" DEFAULT ", to_string(literal)]
    defp default_expr({:ok, %{} = map}) do
      default = Ecto.Adapter.json_library().encode!(map)
      [" DEFAULT ", [?', escape_string(default), ?']]
    end
    defp default_expr({:ok, {:fragment, expr}}),
      do: [" DEFAULT ", expr]
    defp default_expr(:error),
      do: []

    defp index_expr(literal) when is_binary(literal),
      do: literal
    defp index_expr(literal), do: quote_name(literal)

    defp engine_expr(storage_engine),
      do: [" ENGINE = ", String.upcase(to_string(storage_engine || "INNODB"))]

    defp options_expr(nil),
      do: []
    defp options_expr(keyword) when is_list(keyword),
      do: error!(nil, "MySQL adapter does not support keyword lists in :options")
    defp options_expr(options),
      do: [?\s, to_string(options)]

    defp column_type(type, opts) do
      size      = Keyword.get(opts, :size)
      precision = Keyword.get(opts, :precision)
      scale     = Keyword.get(opts, :scale)
      type_name = ecto_to_db(type)

      cond do
        size            -> [type_name, ?(, to_string(size), ?)]
        precision       -> [type_name, ?(, to_string(precision), ?,, to_string(scale || 0), ?)]
        type == :string -> [type_name, "(255)"]
        true            -> type_name
      end
    end

    defp constraint_expr(%Reference{} = ref, table, name),
      do: [", ADD CONSTRAINT ", reference_name(ref, table, name),
           " FOREIGN KEY (", quote_name(name), ?),
           " REFERENCES ", quote_table(table.prefix, ref.table),
           ?(, quote_name(ref.column), ?),
           reference_on_delete(ref.on_delete), reference_on_update(ref.on_update)]

    defp reference_expr(%Reference{} = ref, table, name),
      do: [", CONSTRAINT ", reference_name(ref, table, name),
           " FOREIGN KEY (", quote_name(name), ?),
           " REFERENCES ", quote_table(table.prefix, ref.table),
           ?(, quote_name(ref.column), ?),
           reference_on_delete(ref.on_delete), reference_on_update(ref.on_update)]

    defp reference_name(%Reference{name: nil}, table, column),
      do: quote_name("#{table.name}_#{column}_fkey")
    defp reference_name(%Reference{name: name}, _table, _column),
      do: quote_name(name)

    defp reference_column_type(:serial, _opts), do: "BIGINT UNSIGNED"
    defp reference_column_type(:bigserial, _opts), do: "BIGINT UNSIGNED"
    defp reference_column_type(type, opts), do: column_type(type, opts)

    defp reference_on_delete(:nilify_all), do: " ON DELETE SET NULL"
    defp reference_on_delete(:delete_all), do: " ON DELETE CASCADE"
    defp reference_on_delete(:restrict), do: " ON DELETE RESTRICT"
    defp reference_on_delete(_), do: []

    defp reference_on_update(:nilify_all), do: " ON UPDATE SET NULL"
    defp reference_on_update(:update_all), do: " ON UPDATE CASCADE"
    defp reference_on_update(:restrict), do: " ON UPDATE RESTRICT"
    defp reference_on_update(_), do: []

    ## Helpers

    defp get_source(query, sources, ix, source) do
      {expr, name, _schema} = elem(sources, ix)
      {expr || paren_expr(source, sources, query), name}
    end

    defp quote_name(name)
    defp quote_name(name) when is_atom(name),
      do: quote_name(Atom.to_string(name))
    defp quote_name(name) do
      if String.contains?(name, "`") do
        error!(nil, "bad field name #{inspect name}")
      end

      [?`, name, ?`]
    end

    defp quote_table(nil, name),    do: quote_table(name)
    defp quote_table(prefix, name), do: [quote_table(prefix), ?., quote_table(name)]

    defp quote_table(name) when is_atom(name),
      do: quote_table(Atom.to_string(name))
    defp quote_table(name) do
      if String.contains?(name, "`") do
        error!(nil, "bad table name #{inspect name}")
      end
      [?`, name, ?`]
    end

    defp intersperse_map(list, separator, mapper, acc \\ [])
    defp intersperse_map([], _separator, _mapper, acc),
      do: acc
    defp intersperse_map([elem], _separator, mapper, acc),
      do: [acc | mapper.(elem)]
    defp intersperse_map([elem | rest], separator, mapper, acc),
      do: intersperse_map(rest, separator, mapper, [acc, mapper.(elem), separator])

    defp if_do(condition, value) do
      if condition, do: value, else: []
    end

    defp escape_string(value) when is_binary(value) do
      value
      |> :binary.replace("'", "''", [:global])
      |> :binary.replace("\\", "\\\\", [:global])
    end

    defp ecto_cast_to_db(:id, _query), do: "unsigned"
    defp ecto_cast_to_db(:integer, _query), do: "unsigned"
    defp ecto_cast_to_db(:string, _query), do: "char"
    defp ecto_cast_to_db(type, query), do: ecto_to_db(type, query)

    defp ecto_to_db(type, query \\ nil)
    defp ecto_to_db({:array, _}, query),
      do: error!(query, "Array type is not supported by MySQL")
    defp ecto_to_db(:id, _query),             do: "integer"
    defp ecto_to_db(:serial, _query),         do: "bigint unsigned not null auto_increment"
    defp ecto_to_db(:bigserial, _query),      do: "bigint unsigned not null auto_increment"
    defp ecto_to_db(:binary_id, _query),      do: "binary(16)"
    defp ecto_to_db(:string, _query),         do: "varchar"
    defp ecto_to_db(:float, _query),          do: "double"
    defp ecto_to_db(:binary, _query),         do: "blob"
    defp ecto_to_db(:uuid, _query),           do: "binary(16)" # MySQL does not support uuid
    defp ecto_to_db(:map, _query),            do: "text"
    defp ecto_to_db({:map, _}, _query),       do: "text"
    defp ecto_to_db(:utc_datetime, _query),   do: "datetime"
    defp ecto_to_db(:naive_datetime, _query), do: "datetime"
    defp ecto_to_db(other, _query),           do: Atom.to_string(other)

    defp error!(nil, message) do
      raise ArgumentError, message
    end
    defp error!(query, message) do
      raise Ecto.QueryError, query: query, message: message
    end
  end
end
