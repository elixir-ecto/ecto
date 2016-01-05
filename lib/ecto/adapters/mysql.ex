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
    * `:pool` - The connection pool module, defaults to `Ecto.Pools.Poolboy`
    * `:pool_timeout` - The default timeout to use on pool calls, defaults to `5000`
    * `:timeout` - The default timeout to use on queries, defaults to `15000`
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
    * `:after_connect` - A `{mod, fun, args}` to be invoked after a connection is established

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

  ## Custom MySQL types

  def loaders(:map, type), do: [&json_decode/1, type]
  def loaders(:boolean, type), do: [&bool_decode/1, type]
  def loaders(:binary_id, type), do: [Ecto.UUID, type]
  def loaders({:embed, _} = type, _),
    do: [&json_decode/1, &Ecto.Adapters.SQL.load_embed(type, &1)]
  def loaders(_primitive, type), do: [type]

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
    database  = Keyword.fetch!(opts, :database)
    charset   = Keyword.get(opts, :charset, "utf8")

    extra = ""

    if collation = Keyword.get(opts, :collation) do
      extra =  extra <> " DEFAULT COLLATE = #{collation}"
    end

    {output, status} =
      run_with_mysql opts, "CREATE DATABASE `" <> database <>
                           "` DEFAULT CHARACTER SET = #{charset} " <> extra

    cond do
      status == 0 -> :ok
      String.contains?(output, "database exists") -> {:error, :already_up}
      true                                        -> {:error, output}
    end
  end

  @doc false
  def storage_down(opts) do
    {output, status} = run_with_mysql(opts, "DROP DATABASE `#{opts[:database]}`")

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
  def insert(repo, %{source: {prefix, source}, autogenerate_id: {key, :id}}, params, [key], opts) do
    {fields, values} = :lists.unzip(params)
    sql = @conn.insert(prefix, source, fields, [fields], [])
    case Ecto.Adapters.SQL.query(repo, sql, values, opts) do
      {:ok, %{num_rows: 1, last_insert_id: last_insert_id}} ->
        {:ok, [{key, last_insert_id}]}
      {:error, err} ->
        case @conn.to_constraints(err) do
          []          -> raise err
          constraints -> {:invalid, constraints}
        end
    end
  end

  def insert(repo, schema_meta, params, [], opts) do
    super(repo, schema_meta, params, [], opts)
  end

  def insert(_repo, %{schema: schema}, _params, returning, _opts) do
    raise ArgumentError, "MySQL does not support :read_after_writes in schemas for non-primary keys. " <>
                         "The following fields in #{inspect schema} are tagged as such: #{inspect returning}"
  end
end
