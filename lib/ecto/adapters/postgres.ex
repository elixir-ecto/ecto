if Code.ensure_loaded?(Postgrex.Connection) do
  defmodule Ecto.Adapters.Postgres do
    @moduledoc """
    This is the adapter module for PostgreSQL. It handles and pools the
    connections to the postgres database with poolboy.

    ## Options

    The options should be given via the repository configuration:

      * `:hostname` - Server hostname
      * `:port` - Server port (default: 5432)
      * `:username` - Username
      * `:password` - User password
      * `:size` - The number of connections to keep in the pool
      * `:max_overflow` - The maximum overflow of connections (see poolboy docs)
      * `:parameters` - Keyword list of connection parameters
      * `:ssl` - Set to true if ssl should be used (default: false)
      * `:ssl_opts` - A list of ssl options, see ssl docs
      * `:lazy` - If false all connections will be started immediately on Repo startup (default: true)

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
    def all(repo, query, params, opts) do
      sql    = SQL.all(query)
      fields = process_fields(query.select.fields, query.sources)
      %Postgrex.Result{rows: rows} = query(repo, sql, Map.values(params), opts)
      Enum.map(rows, &process_row(&1, fields))
    end

    @doc false
    def update_all(repo, query, values, params, opts) do
      sql = SQL.update_all(query, values)
      %Postgrex.Result{num_rows: nrows} = query(repo, sql, Map.values(params), opts)
      nrows
    end

    @doc false
    def delete_all(repo, query, params, opts) do
      sql = SQL.delete_all(query)
      %Postgrex.Result{num_rows: nrows} = query(repo, sql, Map.values(params), opts)
      nrows
    end

    @doc false
    def insert(repo, source, params, returning, opts) do
      {fields, values} = :lists.unzip(params)
      sql = SQL.insert(source, fields, returning)

      case query(repo, sql, values, opts) do
        %Postgrex.Result{num_rows: 1, rows: nil} ->
          {:ok, {}}
        %Postgrex.Result{num_rows: 1, rows: [values]} ->
          {:ok, values}
      end
    end

    @doc false
    def update(repo, source, filter, fields, returning, opts) do
      {filter, values1} = :lists.unzip(filter)
      {fields, values2} = :lists.unzip(fields)
      sql = SQL.update(source, filter, fields, returning)

      case query(repo, sql, values1 ++ values2, opts) do
        %Postgrex.Result{rows: [values]} ->
          {:ok, values}
        %Postgrex.Result{rows: []} ->
          {:error, :stale}
      end
    end

    @doc false
    def delete(repo, source, filter, opts) do
      {filter, values} = :lists.unzip(filter)

      sql = SQL.delete(source, filter)

      case query(repo, sql, values, opts) do
        %Postgrex.Result{num_rows: 1} ->
          :ok
        %Postgrex.Result{num_rows: 0} ->
          {:error, :stale}
      end
    end

    @doc """
    Run custom SQL query on given repo.

    ## Options
      `:timeout` - The time in milliseconds to wait for the call to finish,
                   `:infinity` will wait indefinitely (default: 5000);

    ## Examples

        iex> Postgres.query(MyRepo, "SELECT $1 + $2", [40, 2])
        %Postgrex.Result{command: :select, columns: ["?column?"], rows: [{42}], num_rows: 1}
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

      # TODO: Remove those to integers calls
      pool_opts = pool_opts
        |> Keyword.update(:size, 5, &to_integer(&1))
        |> Keyword.update(:max_overflow, 10, &to_integer(&1))

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

    defp to_integer(int) when is_integer(int), do: int
    defp to_integer(bin) when is_binary(bin),  do: String.to_integer(bin)

    defp repo_pool(repo) do
      pid = repo.__postgres__(:pool_name) |> Process.whereis

      if is_nil(pid) or not Process.alive?(pid) do
        raise ArgumentError, "repo #{inspect repo} is not started"
      end

      pid
    end

    ## Rows processing

    defp process_fields(fields, sources) do
      Enum.map fields, fn
        {:&, _, [idx]} ->
          {_source, model} = elem(sources, idx)
          {length(model.__schema__(:fields)), model}
        _ ->
          {1, nil}
      end
    end

    defp process_row(row, fields) do
      Enum.map_reduce(fields, 0, fn
        {1, nil}, idx ->
          {elem(row, idx), idx + 1}
        {count, model}, idx ->
          if all_nil?(row, idx, count) do
            {nil, idx + count}
          else
            {model.__schema__(:load, idx, row), idx + count}
          end
      end) |> elem(0)
    end

    defp all_nil?(_tuple, _idx, 0), do: true
    defp all_nil?(tuple, idx, _count) when elem(tuple, idx) != nil, do: false
    defp all_nil?(tuple, idx, count), do: all_nil?(tuple, idx + 1, count - 1)

    ## Postgrex casting

    defp formatter(%TypeInfo{sender: "uuid"}), do: :binary
    defp formatter(_), do: nil

    defp decoder(%TypeInfo{sender: "uuid"}, :binary, _default, param) do
      param
    end

    defp decoder(_type, _format, default, param) do
      default.(param)
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
          stacktrace = System.stacktrace
          do_rollback(repo, worker, opts)
          :erlang.raise(type, term, stacktrace)
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

      if port = database[:port] do
        command = ~s(PGPORT=#{port} ) <> command
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
