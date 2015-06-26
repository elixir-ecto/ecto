defmodule Ecto.Adapters.MySQL do
  @moduledoc """
  Adapter module for MySQL.

  It handles and pools the connections to the MySQL
  database using `mariaex` and a connection pool,
  such as `poolboy`.

  ## Options

  MySQL options split in different categories described
  below. All options should be given via the repository
  configuration.

  ### Compile time options

  Those options should be set in the config file and require
  recompilation in order to make an effect.

    * `:adapter` - The adapter name, in this case, `Ecto.Adapters.MySQL`
    * `:pool` - The connection pool module, defaults to `Ecto.Adapters.Poolboy`
    * `:timeout` - The default timeout to use on queries, defaults to `5000`
    * `:log_level` - The level to use when logging queries (default: `:debug`)

  ### Connection options

    * `:hostname` - Server hostname
    * `:port` - Server port (default: 3306)
    * `:username` - Username
    * `:password` - User password
    * `:parameters` - Keyword list of connection parameters
    * `:ssl` - Set to true if ssl should be used (default: false)
    * `:ssl_opts` - A list of ssl options, see ssl docs
    * `:connect_timeout` - The timeout in miliseconds for establishing new connections (default: 5000)

  ### Pool options

  All pools should support the following options and can support other options,
  see `Ecto.Adapters.Poolboy`.

    * `:size` - The number of connections to keep in the pool (default: 10)

  ### Storage options

    * `:charset` - the database encoding (default: "utf8")
    * `:collation` - the collation order

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

  ## Storage API

  @doc false
  def storage_up(opts) do
    database  = Keyword.fetch!(opts, :database)
    charset   = Keyword.get(opts, :charset, "utf8")

    extra = ""

    if collation = Keyword.get(opts, :collation) do
      extra =  extra <> " DEFAULT COLLATE = #{collation}"
    end

    {output, status} =
      run_with_mysql opts, "CREATE DATABASE " <> database <>
                           " DEFAULT CHARACTER SET = #{charset} " <> extra

    cond do
      status == 0 -> :ok
      String.contains?(output, "database exists") -> {:error, :already_up}
      true                                        -> {:error, output}
    end
  end

  @doc false
  def storage_down(opts) do
    {output, status} = run_with_mysql(opts, "DROP DATABASE #{opts[:database]}")

    cond do
      status == 0                               -> :ok
      String.contains?(output, "doesn't exist") -> {:error, :already_down}
      true                                      -> {:error, output}
    end
  end

  defp run_with_mysql(database, sql_command) do
    unless System.find_executable("mysql") do
      raise "could not find executable `mysql` in path, " <>
            "please guarantee it is available before running ecto commands"
    end

    env = []

    if password = database[:password] do
      env = [{"MYSQL_PWD", password}|env]
    end

    host = database[:hostname] || System.get_env("MYSQL_HOST") || "localhost"
    port = database[:port] || System.get_env("MYSQL_TCP_PORT") || "3306"
    args = ["--silent", "-u", database[:username], "-h", host, "-P", to_string(port), "-e", sql_command]
    System.cmd("mysql", args, env: env, stderr_to_stdout: true)
  end

  @doc false
  def supports_ddl_transaction? do
    false
  end

  @doc false
  def insert(_repo, source, _params, _autogen, [_|_] = returning, _opts) do
    raise ArgumentError, "MySQL does not support :read_after_writes in models. " <>
                         "The following fields in #{inspect source} have tagged as such: #{inspect returning}"
  end

  def insert(repo, source, params, {pk, :id, nil}, [], opts) do
    {fields, values} = :lists.unzip(params)
    sql = @conn.insert(source, fields, [])
    case Ecto.Adapters.SQL.query(repo, sql, values, opts) do
      %{num_rows: 1, last_insert_id: last_insert_id} ->
        {:ok, [{pk, last_insert_id}]}
    end
  end

  def insert(repo, source, params, autogen, [], opts) do
    super(repo, source, params, autogen, [], opts)
  end

  @doc false
  def update(repo, source, fields, filter, _autogenerate, returning, opts) do
    {fields, values1} = :lists.unzip(fields)
    {filter, values2} = :lists.unzip(filter)
    sql = @conn.update(source, fields, filter, returning)
    case Ecto.Adapters.SQL.query(repo, sql, values1 ++ values2, opts) do
      %{num_rows: 0} -> {:error, :stale}
      %{num_rows: _} -> {:ok, []}
    end
  end

  @doc false
  def delete(repo, source, filter, _autogenerate, opts) do
    {filter, values} = :lists.unzip(filter)
    case Ecto.Adapters.SQL.query(repo, @conn.delete(source, filter, []), values, opts) do
      %{num_rows: 0} -> {:error, :stale}
      %{num_rows: _} -> {:ok, []}
    end
  end
end
