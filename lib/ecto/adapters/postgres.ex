if Code.ensure_loaded?(Postgrex.Connection) do
  defmodule Ecto.Adapters.Postgres do
    @moduledoc """
    This is the adapter module for PostgreSQL. It handles and pools the
    connections to the postgres database with poolboy.

    ## Options

    The options should be given via `Ecto.Repo.conf/0`.

    `:hostname` - Server hostname;
    `:port` - Server port (default: 5432);
    `:username` - Username;
    `:password` - User password;
    `:size` - The number of connections to keep in the pool;
    `:max_overflow` - The maximum overflow of connections (see poolboy docs);
    `:parameters` - Keyword list of connection parameters;
    `:ssl` - Set to true if ssl should be used (default: false);
    `:ssl_opts` - A list of ssl options, see ssl docs;
    `:lazy` - If false all connections will be started immediately on Repo startup (default: true)
    """

    @behaviour Ecto.Adapter
    @behaviour Ecto.Adapter.Migrations
    @behaviour Ecto.Adapter.Storage
    @behaviour Ecto.Adapter.Transactions
    @behaviour Ecto.Adapter.TestTransactions

    @default_port 5432
    @timeout 5000

    alias Ecto.Adapters.Postgres.SQL
    alias Ecto.Adapters.Postgres.Worker
    alias Ecto.Associations.Assoc
    alias Ecto.Query.QueryExpr
    alias Ecto.Query.Util
    alias Postgrex.TypeInfo

    ## Adapter API

    @doc false
    defmacro __using__(_opts) do
      quote do
        def __postgres__(:pool_name) do
          __MODULE__.Pool
        end
      end
    end

    @doc false
    def start_link(repo, opts) do
      {pool_opts, worker_opts} = prepare_start(repo, opts)
      :poolboy.start_link(pool_opts, worker_opts)
    end

    @doc false
    def stop(repo) do
      pool = repo_pool(repo)
      :poolboy.stop(pool)
    end

    @doc false
    def all(repo, query, opts) do
      pg_query = %{query | select: normalize_select(query.select)}

      {sql, params} = SQL.select(pg_query)
      %Postgrex.Result{rows: rows} = query(repo, sql, params, opts)

      # Transform each row based on select expression
      transformed =
        Enum.map(rows, fn row ->
          values = Tuple.to_list(row)
          transform_row(pg_query.select.expr, values, pg_query.sources) |> elem(0)
        end)

      transformed
      |> Ecto.Associations.Assoc.run(query)
      |> preload(repo, query)
    end

    @doc false
    def insert(repo, model, opts) do
      module    = model.__struct__
      returning = module.__schema__(:keywords, model)
        |> Enum.filter(fn {_, val} -> val == nil end)
        |> Keyword.keys

      {sql, params} = SQL.insert(model, returning)

      case query(repo, sql, params, opts) do
        %Postgrex.Result{rows: [values]} ->
          Enum.zip(returning, Tuple.to_list(values))
        _ ->
          []
      end
    end

    @doc false
    def update(repo, model, opts) do
      {sql, params} = SQL.update(model)
      %Postgrex.Result{num_rows: nrows} = query(repo, sql, params, opts)
      nrows
    end

    @doc false
    def update_all(repo, query, values, external, opts) do
      {sql, params} = SQL.update_all(query, values, external)
      %Postgrex.Result{num_rows: nrows} = query(repo, sql, params, opts)
      nrows
    end

    @doc false
    def delete(repo, model, opts) do
      {sql, params} = SQL.delete(model)
      %Postgrex.Result{num_rows: nrows} = query(repo, sql, params, opts)
      nrows
    end

    @doc false
    def delete_all(repo, query, opts) do
      {sql, params} = SQL.delete_all(query)
      %Postgrex.Result{num_rows: nrows} = query(repo, sql, params, opts)
      nrows
    end

    @doc """
    Run custom SQL query on given repo.

    ## Options
      `:timeout` - The time in milliseconds to wait for the call to finish,
                   `:infinity` will wait indefinitely (default: 5000);

    ## Examples

        iex> Postgres.query(MyRepo, "SELECT $1 + $2", [40, 2])
        Postgrex.Result[command: :select, columns: ["?column?"], rows: [{42}], num_rows: 1]
    """
    def query(repo, sql, params, opts \\ []) do
      pool = repo_pool(repo)

      opts = Keyword.put_new(opts, :timeout, @timeout)
      repo.log({:query, sql}, fn ->
        use_worker(pool, opts[:timeout], fn worker ->
          Worker.query!(worker, sql, params, opts)
        end)
      end)
    end

    defp prepare_start(repo, opts) do
      pool_name = repo.__postgres__(:pool_name)
      {pool_opts, worker_opts} = Dict.split(opts, [:size, :max_overflow])

      pool_opts = pool_opts
        |> Keyword.update(:size, 5, &String.to_integer(&1))
        |> Keyword.update(:max_overflow, 10, &String.to_integer(&1))

      pool_opts = [
        name: {:local, pool_name},
        worker_module: Worker ] ++ pool_opts

      worker_opts = worker_opts
        |> Keyword.put(:formatter, &formatter/1)
        |> Keyword.put(:decoder, &decoder/4)
        |> Keyword.put(:encoder, &encoder/3)
        |> Keyword.put_new(:port, @default_port)

      {pool_opts, worker_opts}
    end

    @doc false
    def normalize_select(%QueryExpr{expr: {:assoc, _, [_, _]} = assoc} = expr) do
      %{expr | expr: normalize_assoc(assoc)}
    end

    def normalize_select(%QueryExpr{expr: _} = expr), do: expr

    defp normalize_assoc({:assoc, _, [_, _]} = assoc) do
      {var, fields} = Assoc.decompose_assoc(assoc)
      normalize_assoc(var, fields)
    end

    defp normalize_assoc(var, fields) do
      nested = Enum.map(fields, fn {_field, nested} ->
        {var, fields} = Assoc.decompose_assoc(nested)
        normalize_assoc(var, fields)
      end)
      {var, nested}
    end

    defp preload(results, repo, query) do
      pos = Util.locate_var(query.select.expr, {:&, [], [0]})
      fields = Enum.map(query.preloads, &(&1.expr)) |> Enum.concat
      Ecto.Associations.Preloader.run(results, repo, fields, pos)
    end

    defp repo_pool(repo) do
      pid = repo.__postgres__(:pool_name) |> Process.whereis

      if is_nil(pid) or not Process.alive?(pid) do
        raise ArgumentError, message: "repo #{inspect repo} is not started"
      end

      pid
    end

    ## Result set transformation

    defp transform_row({:{}, _, list}, values, sources) do
      {result, values} = transform_row(list, values, sources)
      {List.to_tuple(result), values}
    end

    defp transform_row({:&, _, [_]} = var, values, sources) do
      model = Util.find_source(sources, var) |> Util.model
      model_size = length(model.__schema__(:field_names))
      {model_values, values} = Enum.split(values, model_size)
      if Enum.all?(model_values, &(is_nil(&1))) do
        {nil, values}
      else
        {model.__schema__(:allocate, model_values), values}
      end
    end

    # Skip records
    defp transform_row({first, _} = tuple, values, sources) when not is_atom(first) do
      {result, values} = transform_row(Tuple.to_list(tuple), values, sources)
      {List.to_tuple(result), values}
    end

    defp transform_row(list, values, sources) when is_list(list) do
      {result, values} = Enum.reduce(list, {[], values}, fn elem, {res, values} ->
        {result, values} = transform_row(elem, values, sources)
        {[result|res], values}
      end)

      {Enum.reverse(result), values}
    end

    defp transform_row(_, values, _entities) do
      [value|values] = values
      {value, values}
    end

    ## Postgrex casting

    defp formatter(%TypeInfo{sender: "uuid"}), do: :binary
    defp formatter(_), do: nil

    defp decoder(%TypeInfo{sender: "interval"}, :binary, default, param) do
      {mon, day, sec} = default.(param)
      %Ecto.Interval{year: 0, month: mon, day: day, hour: 0, min: 0, sec: sec}
    end

    defp decoder(%TypeInfo{sender: sender}, :binary, default, param)
        when sender in ["timestamp", "timestamptz"] do
      default.(param)
      |> Ecto.DateTime.from_erl
    end

    defp decoder(%TypeInfo{sender: "date"}, :binary, default, param) do
      default.(param)
      |> Ecto.Date.from_erl
    end

    defp decoder(%TypeInfo{sender: sender}, :binary, default, param)
        when sender in ["time", "timetz"] do
      default.(param)
      |> Ecto.Time.from_erl
    end

    defp decoder(%TypeInfo{sender: "uuid"}, :binary, _default, param) do
      param
    end

    defp decoder(_type, _format, default, param) do
      default.(param)
    end

    defp encoder(type, default, %Ecto.Tagged{value: value}) do
      encoder(type, default, value)
    end

    defp encoder(%TypeInfo{sender: "interval"}, default, %Ecto.Interval{} = interval) do
      mon = interval.year * 12 + interval.month
      day = interval.day
      sec = interval.hour * 3600 + interval.min * 60 + interval.sec
      default.({mon, day, sec})
    end

    defp encoder(%TypeInfo{sender: sender}, default, %Ecto.DateTime{} = datetime)
        when sender in ["timestamp", "timestamptz"] do
      Ecto.DateTime.to_erl(datetime)
      |> default.()
    end

    defp encoder(%TypeInfo{sender: "date"}, default, %Ecto.Date{} = date) do
      Ecto.Date.to_erl(date)
      |> default.()
    end

    defp encoder(%TypeInfo{sender: sender}, default, %Ecto.Time{} = time)
        when sender in ["time", "timetz"] do
      Ecto.Time.to_erl(time)
      |> default.()
    end

    defp encoder(%TypeInfo{sender: "uuid"}, _default, uuid) do
      uuid
    end

    defp encoder(_type, default, param) do
      default.(param)
    end

    ## Transaction API

    @doc false
    def transaction(repo, opts, fun) do
      pool = repo_pool(repo)

      opts = Keyword.put_new(opts, :timeout, @timeout)
      worker = checkout_worker(pool, opts[:timeout])

      try do
        do_begin(repo, worker, opts)
        value = fun.()
        do_commit(repo, worker, opts)
        {:ok, value}
      catch
        :throw, {:ecto_rollback, value} ->
          do_rollback(repo, worker, opts)
          {:error, value}
        type, term ->
          do_rollback(repo, worker, opts)
          :erlang.raise(type, term, System.stacktrace)
      after
        checkin_worker(pool)
      end
    end

    @doc false
    def rollback(_repo, value) do
      throw {:ecto_rollback, value}
    end

    defp use_worker(pool, timeout, fun) do
      key = {:ecto_transaction_pid, pool}

      if value = Process.get(key) do
        in_transaction = true
        worker = elem(value, 0)
      else
        worker = :poolboy.checkout(pool, true, timeout)
      end

      try do
        fun.(worker)
      after
        if !in_transaction do
          :poolboy.checkin(pool, worker)
        end
      end
    end

    defp checkout_worker(pool, timeout) do
      key = {:ecto_transaction_pid, pool}

      case Process.get(key) do
        {worker, counter} ->
          Process.put(key, {worker, counter + 1})
          worker
        nil ->
          worker = :poolboy.checkout(pool, true, timeout)
          Worker.monitor_me(worker)
          Process.put(key, {worker, 1})
          worker
      end
    end

    defp checkin_worker(pool) do
      key = {:ecto_transaction_pid, pool}

      case Process.get(key) do
        {worker, 1} ->
          Worker.demonitor_me(worker)
          :poolboy.checkin(pool, worker)
          Process.delete(key)
        {worker, counter} ->
          Process.put(key, {worker, counter - 1})
      end
      :ok
    end

    defp do_begin(repo, worker, opts) do
      repo.log(:begin, fn ->
        Worker.begin!(worker, opts)
      end)
    end

    defp do_rollback(repo, worker, opts) do
      repo.log(:rollback, fn ->
        Worker.rollback!(worker, opts)
      end)
    end

    defp do_commit(repo, worker, opts) do
      repo.log(:commit, fn ->
        Worker.commit!(worker, opts)
      end)
    end

    ## Test transaction API

    @doc false
    def begin_test_transaction(repo, opts \\ []) do
      pool = repo_pool(repo)
      opts = Keyword.put_new(opts, :timeout, @timeout)

      :poolboy.transaction(pool, fn worker ->
        do_begin(repo, worker, opts)
      end, opts[:timeout])
    end

    @doc false
    def rollback_test_transaction(repo, opts \\ []) do
      pool = repo_pool(repo)
      opts = Keyword.put_new(opts, :timeout, @timeout)

      :poolboy.transaction(pool, fn worker ->
        do_rollback(repo, worker, opts)
      end, opts[:timeout])
    end

    ## Storage API

    @doc false
    def storage_up(opts) do
      # TODO: allow the user to specify those options either in the Repo or on command line
      database_options = ~s(TEMPLATE=template0 ENCODING='UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8')

      output = run_with_psql opts, "CREATE DATABASE #{opts[:database]} " <> database_options

      cond do
        String.length(output) == 0                 -> :ok
        String.contains?(output, "already exists") -> {:error, :already_up}
        true                                       -> {:error, output}
      end
    end

    @doc false
    def storage_down(opts) do
      output = run_with_psql(opts, "DROP DATABASE #{opts[:database]}")

      cond do
        String.length(output) == 0                 -> :ok
        String.contains?(output, "does not exist") -> {:error, :already_down}
        true                                       -> {:error, output}
      end
    end

    defp run_with_psql(database, sql_command) do
      command = ""

      if password = database[:password] do
        command = ~s(PGPASSWORD=#{password} )
      end

      if username = database[:username] do
        command = ~s(PGUSER=#{username} ) <> command
      end

      command =
        command <>
        ~s(psql --quiet ) <>
        ~s(template1 ) <>
        ~s(--host #{database[:hostname]} ) <>
        ~s(-c "#{sql_command};" )

      String.to_char_list(command)
      |> :os.cmd
      |> List.to_string
    end

    ## Migration API

    @migrate_opts [timeout: :infinity]

    @doc false
    def migrate_up(repo, version, commands) do
      case check_migration_version(repo, version) do
        %Postgrex.Result{num_rows: 0} ->
          transaction(repo, [], fn ->
            Enum.each(commands, &query(repo, &1, [], @migrate_opts))
            insert_migration_version(repo, version)
          end)
          :ok
        _ ->
          :already_up
      end
    end

    @doc false
    def migrate_down(repo, version, commands) do
      case check_migration_version(repo, version) do
        %Postgrex.Result{num_rows: 0} ->
          :missing_up
        _ ->
          transaction(repo, [], fn ->
            Enum.each(commands, &query(repo, &1, [], @migrate_opts))
            delete_migration_version(repo, version)
          end)
          :ok
      end
    end

    @doc false
    def migrated_versions(repo) do
      create_migrations_table(repo)
      %Postgrex.Result{rows: rows} = query(repo, "SELECT version FROM schema_migrations", [])
      Enum.map(rows, &elem(&1, 0))
    end

    defp create_migrations_table(repo) do
      query(repo, "CREATE TABLE IF NOT EXISTS schema_migrations (id serial primary key, version bigint)", [])
    end

    defp check_migration_version(repo, version) do
      create_migrations_table(repo)
      query(repo, "SELECT version FROM schema_migrations WHERE version = #{version}", [])
    end

    defp insert_migration_version(repo, version) do
      query(repo, "INSERT INTO schema_migrations(version) VALUES (#{version})", [])
    end

    defp delete_migration_version(repo, version) do
      query(repo, "DELETE FROM schema_migrations WHERE version = #{version}", [])
    end
  end
end
