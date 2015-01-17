if Code.ensure_loaded?(Postgrex.Connection) do
  defmodule Ecto.Adapters.Postgres do
    @moduledoc """
    Adapter module for PostgreSQL.

    It handles and pools the connections to the postgres
    database with poolboy.

    ## Options

    Postgrex options split in different categories described
    below. All options should be given via the repository
    configuration.

    ### Connection options

      * `:hostname` - Server hostname
      * `:port` - Server port (default: 5432)
      * `:username` - Username
      * `:password` - User password
      * `:parameters` - Keyword list of connection parameters
      * `:ssl` - Set to true if ssl should be used (default: false)
      * `:ssl_opts` - A list of ssl options, see Erlang's `ssl` docs

    ### Pool options

      * `:size` - The number of connections to keep in the pool
      * `:max_overflow` - The maximum overflow of connections (see poolboy docs)
      * `:lazy` - If false all connections will be started immediately on Repo startup (default: true)

    ### Storage options

      * `:template` - the template to create the database from (default: "template0")
      * `:encoding` - the database encoding (default: "UTF8")
      * `:lc_collate` - the collation order (default: "en_US.UTF-8")
      * `:lc_ctype` - the character classification (default: "en_US.UTF-8")

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

    ## Public API

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

    defp prepare_start(repo, opts) do
      pool_name = repo.__postgres__(:pool_name)
      {pool_opts, worker_opts} = Dict.split(opts, [:size, :max_overflow])

      pool_opts = pool_opts
        |> Keyword.put_new(:size, 5)
        |> Keyword.put_new(:max_overflow, 10)

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

    defp repo_pool(repo) do
      pid = repo.__postgres__(:pool_name) |> Process.whereis

      if is_nil(pid) or not Process.alive?(pid) do
        raise ArgumentError, "repo #{inspect repo} is not started"
      end

      pid
    end

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

    ## Query API

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

    ## Transaction API

    @doc false
    def transaction(repo, opts, fun) do
      pool = repo_pool(repo)

      opts   = Keyword.put_new(opts, :timeout, @timeout)
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

    ## TODO: Make those in sync with the actual query

    defp do_begin(repo, worker, opts) do
      repo.log({:query, "BEGIN TRANSACTION"} , fn ->
        Worker.begin!(worker, opts)
      end)
    end

    defp do_rollback(repo, worker, opts) do
      repo.log({:query, "ROLLBACK"}, fn ->
        Worker.rollback!(worker, opts)
      end)
    end

    defp do_commit(repo, worker, opts) do
      repo.log({:query, "COMMIT"}, fn ->
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
      database   = Keyword.fetch!(opts, :database)
      template   = Keyword.get(opts, :template, "template0")
      encoding   = Keyword.get(opts, :encoding, "UTF8")
      lc_collate = Keyword.get(opts, :lc_collate, "en_US.UTF-8")
      lc_ctype   = Keyword.get(opts, :lc_ctype, "en_US.UTF-8")

      output =
        run_with_psql opts,
          "CREATE DATABASE " <> database <> " " <>
          "TEMPLATE=#{template} ENCODING='#{encoding}' " <>
          "LC_COLLATE='#{lc_collate}' LC_CTYPE='#{lc_ctype}'"

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

    @doc false
    def execute_ddl(repo, definition) do
      ddl_query(repo, SQL.migrate(definition))
      :ok
    end

    @doc false
    def ddl_exists?(repo, object) do
      %Postgrex.Result{rows: [{count}]} = ddl_query(repo, SQL.ddl_exists_query(object))
      count > 0
    end

    defp ddl_query(repo, sql) do
      use_worker(repo_pool(repo), :infinity, fn worker ->
        Worker.query!(worker, sql, [], [timeout: :infinity])
      end)
    end
  end
end
