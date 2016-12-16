defmodule Ecto.Adapters.MySQL do
  @moduledoc """
  Adapter module for MySQL.

  It handles and pools the connections to the MySQL
  database using `mariaex` and a connection pool,
  such as `poolboy`.

  ## Options

  MySQL options split in different categories described
  below. All options should be given via the repository
  configuration. These options are also passed to the module
  specified in the `:pool` option, so check that module's
  documentation for more options.

  ### Compile time options

  Those options should be set in the config file and require
  recompilation in order to make an effect.

    * `:adapter` - The adapter name, in this case, `Ecto.Adapters.MySQL`
    * `:pool` - The connection pool module, defaults to `DBConnection.Poolboy`
    * `:pool_timeout` - The default timeout to use on pool calls, defaults to `5000`
    * `:timeout` - The default timeout to use on queries, defaults to `15000`

  ### Connection options

    * `:hostname` - Server hostname
    * `:port` - Server port (default: 3306)
    * `:username` - Username
    * `:password` - User password
    * `:ssl` - Set to true if ssl should be used (default: false)
    * `:ssl_opts` - A list of ssl options, see Erlang's `ssl` docs
    * `:parameters` - Keyword list of connection parameters
    * `:connect_timeout` - The timeout for establishing new connections (default: 5000)
    * `:socket_options` - Specifies socket configuration

  The `:socket_options` are particularly useful when configuring the size
  of both send and receive buffers. For example, when Ecto starts with a
  pool of 20 connections, the memory usage may quickly grow from 20MB to
  50MB based on the operating system default values for TCP buffers. It is
  advised to stick with the operating system defaults but they can be
  tweaked if desired:

      socket_options: [recbuf: 8192, sndbuf: 8192]

  We also recommend developers to consult the
  [Mariaex documentation](https://hexdocs.pm/mariaex/Mariaex.html#start_link/1)
  for a complete listing of all supported options.

  ### Storage options

    * `:charset` - the database encoding (default: "utf8")
    * `:collation` - the collation order
    * `:dump_path` - where to place dumped structures

  ## Limitations

  There are some limitations when using Ecto with MySQL that one
  needs to be aware of.

  ### Engine

  Since Ecto uses transactions, MySQL users running old versions
  (5.1 and before) must ensure their tables use the InnoDB engine
  as the default (MyISAM) does not support transactions.

  Tables created by Ecto are guaranteed to use InnoDB, regardless
  of the MySQL version.

  ### UUIDs

  MySQL does not support UUID types. Ecto emulates them by using
  `binary(16)`.

  ### Read after writes

  Because MySQL does not support RETURNING clauses in INSERT and
  UPDATE, it does not support the `:read_after_writes` option of
  `Ecto.Schema.field/3`.

  ### DDL Transaction

  MySQL does not support migrations inside transactions as it
  automatically commits after some commands like CREATE TABLE.
  Therefore MySQL migrations does not run inside transactions.

  ### usec in datetime

  Old MySQL versions did not support usec in datetime while
  more recent versions would round or truncate the usec value.

  Therefore, in case the user decides to use microseconds in
  datetimes and timestamps with MySQL, be aware of such
  differences and consult the documentation for your MySQL
  version.
  """

  # Inherit all behaviour from Ecto.Adapters.SQL
  use Ecto.Adapters.SQL, :mariaex

  # And provide a custom storage implementation
  @behaviour Ecto.Adapter.Storage
  @behaviour Ecto.Adapter.Structure

  ## Custom MySQL types

  @doc false
  def loaders(:map, type),            do: [&json_decode/1, type]
  def loaders({:map, _}, type),       do: [&json_decode/1, type]
  def loaders(:boolean, type),        do: [&bool_decode/1, type]
  def loaders(:binary_id, type),      do: [Ecto.UUID, type]
  def loaders({:embed, _} = type, _), do: [&json_decode/1, &Ecto.Adapters.SQL.load_embed(type, &1)]
  def loaders(_, type),               do: [type]

  defp bool_decode(<<0>>), do: {:ok, false}
  defp bool_decode(<<1>>), do: {:ok, true}
  defp bool_decode(0), do: {:ok, false}
  defp bool_decode(1), do: {:ok, true}
  defp bool_decode(x), do: {:ok, x}

  defp json_decode(x) when is_binary(x),
    do: {:ok, Application.get_env(:ecto, :json_library).decode!(x)}
  defp json_decode(x),
    do: {:ok, x}

  ## Storage API

  @doc false
  def storage_up(opts) do
    database = Keyword.fetch!(opts, :database) || raise ":database is nil in repository configuration"
    charset  = opts[:charset] || "utf8"

    command =
      ~s(CREATE DATABASE `#{database}` DEFAULT CHARACTER SET = #{charset})
      |> concat_if(opts[:collation], &"DEFAULT COLLATE = #{&1}")

    {output, status} = run_with_mysql command, opts

    cond do
      status == 0 -> :ok
      String.contains?(output, "database exists") -> {:error, :already_up}
      true                                        -> {:error, output}
    end
  end

  defp concat_if(content, nil, _fun),  do: content
  defp concat_if(content, value, fun), do: content <> " " <> fun.(value)

  @doc false
  def storage_down(opts) do
    database = Keyword.fetch!(opts, :database) || raise ":database is nil in repository configuration"
    {output, status} = run_with_mysql("DROP DATABASE `#{database}`", opts)

    cond do
      status == 0                               -> :ok
      String.contains?(output, "doesn't exist") -> {:error, :already_down}
      true                                      -> {:error, output}
    end
  end

  defp run_with_mysql(sql_command, opts) do
    args = ["--silent", "--execute", sql_command]
    run_with_cmd("mysql", opts, args)
  end

  @doc false
  def supports_ddl_transaction? do
    true
  end

  @doc false
  def insert(repo, %{source: {prefix, source}} = meta, params,
             {_, query_params, _} = on_conflict, returning, opts) do
    key = primary_key!(meta, returning)
    {fields, values} = :lists.unzip(params)
    sql = @conn.insert(prefix, source, fields, [fields], on_conflict, [])
    case Ecto.Adapters.SQL.query(repo, sql, values ++ query_params, opts) do
      {:ok, %{num_rows: 1, last_insert_id: last_insert_id}} ->
        {:ok, last_insert_id(key, last_insert_id)}
      {:ok, %{num_rows: 2, last_insert_id: last_insert_id}} ->
        {:ok, last_insert_id(key, last_insert_id)}
      {:error, err} ->
        case @conn.to_constraints(err) do
          []          -> raise err
          constraints -> {:invalid, constraints}
        end
    end
  end

  defp primary_key!(%{autogenerate_id: {key, :id}}, [key]), do: key
  defp primary_key!(_, []), do: nil
  defp primary_key!(%{schema: schema}, returning) do
    raise ArgumentError, "MySQL does not support :read_after_writes in schemas for non-primary keys. " <>
                         "The following fields in #{inspect schema} are tagged as such: #{inspect returning}"
  end

  defp last_insert_id(nil, _last_insert_id), do: []
  defp last_insert_id(_key, 0), do: []
  defp last_insert_id(key, last_insert_id), do: [{key, last_insert_id}]

  @doc false
  def structure_dump(default, config) do
    table = config[:migration_source] || "schema_migrations"
    path  = config[:dump_path] || Path.join(default, "structure.sql")

    with {:ok, versions} <- select_versions(table, config),
         {:ok, contents} <- mysql_dump(config),
         {:ok, contents} <- append_versions(table, versions, contents) do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, contents)
      {:ok, path}
    end
  end

  defp select_versions(table, config) do
    case run_query(~s[SELECT version FROM `#{table}` ORDER BY version], config) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &hd/1)}
      {:error, %{mariadb: %{code: 1146}}} -> {:ok, []}
      {:error, _} = error -> error
    end
  end

  defp mysql_dump(config) do
    case run_with_cmd("mysqldump", config, ["--no-data", "--routines", config[:database]]) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, output}
    end
  end

  defp append_versions(_table, [], contents) do
    {:ok, contents}
  end
  defp append_versions(table, versions, contents) do
    {:ok,
      contents <>
      ~s[INSERT INTO `#{table}` (version) VALUES ] <>
      Enum.map_join(versions, ", ", &"(#{&1})") <>
      ~s[;\n\n]}
  end

  @doc false
  def structure_load(default, config) do
    path = config[:dump_path] || Path.join(default, "structure.sql")

    args = [
      "--execute", "SET FOREIGN_KEY_CHECKS = 0; SOURCE #{path}; SET FOREIGN_KEY_CHECKS = 1",
      "--database", config[:database]
    ]

    case run_with_cmd("mysql", config, args) do
      {_output, 0} -> {:ok, path}
      {output, _}  -> {:error, output}
    end
  end

  defp run_query(sql, opts) do
    {:ok, _} = Application.ensure_all_started(:mariaex)

    opts =
      opts
      |> Keyword.delete(:name)
      |> Keyword.put(:pool, DBConnection.Connection)
      |> Keyword.put(:backoff_type, :stop)

    {:ok, pid} = Task.Supervisor.start_link

    task = Task.Supervisor.async_nolink(pid, fn ->
      {:ok, conn} = Mariaex.start_link(opts)

      value = Ecto.Adapters.MySQL.Connection.execute(conn, sql, [], opts)
      GenServer.stop(conn)
      value
    end)

    timeout = Keyword.get(opts, :timeout, 15_000)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        {:ok, result}
      {:ok, {:error, error}} ->
        {:error, error}
      {:exit, {%{__struct__: struct} = error, _}}
          when struct in [Mariaex.Error, DBConnection.Error] ->
        {:error, error}
      {:exit, reason}  ->
        {:error, RuntimeError.exception(Exception.format_exit(reason))}
      nil ->
        {:error, RuntimeError.exception("command timed out")}
    end
  end

  defp run_with_cmd(cmd, opts, opt_args) do
    unless System.find_executable(cmd) do
      raise "could not find executable `#{cmd}` in path, " <>
            "please guarantee it is available before running ecto commands"
    end

    env =
      if password = opts[:password] do
        [{"MYSQL_PWD", password}]
      else
        []
      end

    host = opts[:hostname] || System.get_env("MYSQL_HOST") || "localhost"
    port = opts[:port] || System.get_env("MYSQL_TCP_PORT") || "3306"
    args = ["--user", opts[:username], "--host", host, "--port", to_string(port), "--protocol=tcp"] ++ opt_args
    System.cmd(cmd, args, env: env, stderr_to_stdout: true)
  end
end
