defmodule Ecto.Adapters.Postgres do
  @moduledoc """
  Adapter module for PostgreSQL.

  It uses `postgrex` for communicating to the database
  and a connection pool, such as `poolboy`.

  ## Features

    * Full query support (including joins, preloads and associations)
    * Support for transactions
    * Support for data migrations
    * Support for ecto.create and ecto.drop operations
    * Support for transactional tests via `Ecto.Adapters.SQL`

  ## Options

  Postgres options split in different categories described
  below. All options should be given via the repository
  configuration. These options are also passed to the module
  specified in the `:pool` option, so check that module's
  documentation for more options.

  ### Compile time options

  Those options should be set in the config file and require
  recompilation in order to make an effect.

    * `:adapter` - The adapter name, in this case, `Ecto.Adapters.Postgres`

  ### Connection options

    * `:pool` - The connection pool module, defaults to `DBConnection.Poolboy`
    * `:pool_timeout` - The default timeout to use on pool calls, defaults to `5000`
    * `:timeout` - The default timeout to use on queries, defaults to `15000`
    * `:hostname` - Server hostname
    * `:port` - Server port (default: 5432)
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
  [Postgrex documentation](https://hexdocs.pm/postgrex/Postgrex.html#start_link/1)
  for a complete listing of all supported options.

  ### Storage options

    * `:encoding` - the database encoding (default: "UTF8")
    * `:template` - the template to create the database from
    * `:lc_collate` - the collation order
    * `:lc_ctype` - the character classification
    * `:dump_path` - where to place dumped structures

  ## Extensions

  Both PostgreSQL and its adapter for Elixir, Postgrex, support an
  extension system. If you want to use custom extensions for Postgrex
  alongside Ecto, you must define a type module with your extensions.
  Create a new file anywhere in your application with the following:

      Postgrex.Types.define(MyApp.PostgresTypes,
                            [MyExtension.Foo, MyExtensionBar] ++ Ecto.Adapters.Postgres.extensions(),
                            json: Poison)

  Once your type module is defined, you can configure the repository to use it:

      config :my_app, MyApp.Repo, types: MyApp.PostgresTypes

  """

  # Inherit all behaviour from Ecto.Adapters.SQL
  use Ecto.Adapters.SQL, :postgrex

  # And provide a custom storage implementation
  @behaviour Ecto.Adapter.Storage
  @behaviour Ecto.Adapter.Structure

  @doc """
  All Ecto extensions for Postgrex.
  """
  def extensions do
    [Ecto.Adapters.Postgres.Date, Ecto.Adapters.Postgres.Time,
     Ecto.Adapters.Postgres.Timestamp, Ecto.Adapters.Postgres.TimestampTZ]
  end

  # Support arrays in place of IN
  @doc false
  def dumpers({:embed, _} = type, _),  do: [&Ecto.Adapters.SQL.dump_embed(type, &1)]
  def dumpers({:in, sub}, {:in, sub}), do: [{:array, sub}]
  def dumpers(:binary_id, type),       do: [type, Ecto.UUID]
  def dumpers(_, type),                do: [type]

  ## Storage API

  @doc false
  def storage_up(opts) do
    database = Keyword.fetch!(opts, :database) || raise ":database is nil in repository configuration"
    encoding = opts[:encoding] || "UTF8"
    opts     = Keyword.put(opts, :database, "postgres")

    command =
      ~s(CREATE DATABASE "#{database}" ENCODING '#{encoding}')
      |> concat_if(opts[:template], &"TEMPLATE=#{&1}")
      |> concat_if(opts[:lc_ctype], &"LC_CTYPE='#{&1}'")
      |> concat_if(opts[:lc_collate], &"LC_COLLATE='#{&1}'")

    case run_query(command, opts) do
      {:ok, _} ->
        :ok
      {:error, %{postgres: %{code: :duplicate_database}}} ->
        {:error, :already_up}
      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  defp concat_if(content, nil, _fun),  do: content
  defp concat_if(content, value, fun), do: content <> " " <> fun.(value)

  @doc false
  def storage_down(opts) do
    database = Keyword.fetch!(opts, :database) || raise ":database is nil in repository configuration"
    command  = "DROP DATABASE \"#{database}\""
    opts     = Keyword.put(opts, :database, "postgres")

    case run_query(command, opts) do
      {:ok, _} ->
        :ok
      {:error, %{postgres: %{code: :invalid_catalog_name}}} ->
        {:error, :already_down}
      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  @doc false
  def supports_ddl_transaction? do
    true
  end

  @doc false
  def structure_dump(default, config) do
    table = config[:migration_source] || "schema_migrations"
    with {:ok, versions} <- select_versions(table, config),
         {:ok, path} <- pg_dump(default, config),
         do: append_versions(table, versions, path)
  end

  defp select_versions(table, config) do
    case run_query(~s[SELECT version FROM "#{table}" ORDER BY version], config) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &hd/1)}
      {:error, %{postgres: %{code: :undefined_table}}} -> {:ok, []}
      {:error, _} = error -> error
    end
  end

  defp pg_dump(default, config) do
    path = config[:dump_path] || Path.join(default, "structure.sql")
    File.mkdir_p!(Path.dirname(path))

    case run_with_cmd("pg_dump", config, ["--file", path, "--schema-only", "--no-acl",
                                          "--no-owner", config[:database]]) do
      {_output, 0} ->
        {:ok, path}
      {output, _} ->
        {:error, output}
    end
  end

  defp append_versions(_table, [], path) do
    {:ok, path}
  end
  defp append_versions(table, versions, path) do
    sql =
      ~s[INSERT INTO "#{table}" (version) VALUES ] <>
      Enum.map_join(versions, ", ", &"(#{&1})") <>
      ~s[;\n\n]

    File.open!(path, [:append], fn file ->
      IO.write(file, sql)
    end)

    {:ok, path}
  end

  @doc false
  def structure_load(default, config) do
    path = config[:dump_path] || Path.join(default, "structure.sql")
    case run_with_cmd("psql", config, ["--quiet", "--file", path, config[:database]]) do
      {_output, 0} -> {:ok, path}
      {output, _}  -> {:error, output}
    end
  end

  ## Helpers

  defp run_query(sql, opts) do
    {:ok, _} = Application.ensure_all_started(:postgrex)

    opts =
      opts
      |> Keyword.drop([:name, :log])
      |> Keyword.put(:pool, DBConnection.Connection)
      |> Keyword.put(:backoff_type, :stop)

    {:ok, pid} = Task.Supervisor.start_link

    task = Task.Supervisor.async_nolink(pid, fn ->
      {:ok, conn} = Postgrex.start_link(opts)

      value = Ecto.Adapters.Postgres.Connection.execute(conn, sql, [], opts)
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
          when struct in [Postgrex.Error, DBConnection.Error] ->
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
      [{"PGCONNECT_TIMEOUT", "10"}]
    env =
      if password = opts[:password] do
        [{"PGPASSWORD", password}|env]
      else
        env
      end

    args =
      []
    args =
      if username = opts[:username], do: ["-U", username|args], else: args
    args =
      if port = opts[:port], do: ["-p", to_string(port)|args], else: args

    host = opts[:hostname] || System.get_env("PGHOST") || "localhost"
    args = ["--host", host|args]
    args = args ++ opt_args
    System.cmd(cmd, args, env: env, stderr_to_stdout: true)
  end
end
