defmodule Ecto.Adapters.MySQL do
  @moduledoc """
  Adapter module for MySQL.

  It handles and pools the connections to the MySQL
  database using `mariaex` with `poolboy`.

  ## Options

  MySQL options split in different categories described
  below. All options should be given via the repository
  configuration.

  ### Compile time options
  Those options should be set in the config file and require
  recompilation in order to make an effect.
    * `:adapter` - The adapter name, in this case, `Ecto.Adapters.MySQL`
    * `:timeout` - The default timeout to use on queries, defaults to `5000`

  ### Connection options

    * `:hostname` - Server hostname;
    * `:port` - Server port (default: 3306);
    * `:username` - Username;
    * `:password` - User password;
    * `:parameters` - Keyword list of connection parameters;
    * `:ssl` - Set to true if ssl should be used (default: false);
    * `:ssl_opts` - A list of ssl options, see ssl docs;

  ### Pool options

    * `:size` - The number of connections to keep in the pool;
    * `:max_overflow` - The maximum overflow of connections (see poolboy docs);
    * `:lazy` - If false all connections will be started immediately on Repo startup (default: true)

  ### Storage options

    * `:charset` - the database encoding (default: "utf8")
    * `:collation` - the collation order
  """

  use Ecto.Adapters.SQL, :mariaex
  @behaviour Ecto.Adapter.Storage

  ## Storage API

  @doc false
  def storage_up(opts) do
    database  = Keyword.fetch!(opts, :database)
    charset   = Keyword.get(opts, :char_set, "utf8")

    extra = ""

    if collation = Keyword.get(opts, :collation) do
      extra =  extra <> " DEFAULT COLLATE = #{collation}"
    end

    {output, status} =
      run_with_mysql opts, "CREATE DATABASE " <> database <>
                           " DEFAULT CHARACTER SET = #{charset} " <> extra

    cond do
      status == 0                  -> :ok
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

    if port = database[:port] do
      env = [{"MYSQL_TCP_PORT", port}|env]
    end

    args = ["--silent", "-u", database[:username], "-h", database[:hostname], "-e", sql_command]
    System.cmd("mysql", args, env: env, stderr_to_stdout: true)
  end

  @doc false
  def supports_ddl_transaction? do
    false
  end

  @doc false
  def insert(repo, source, params, [], opts) do
    super(repo, source, params, [], opts)
  end

  @doc false
  def insert(repo, source, params, [pk|_], opts) do
    case super(repo, source, params, [pk], opts) do
      {:ok, []} ->
        last_inserted_query = @conn.last_inserted(source, pk)
        Ecto.Adapters.SQL.model(repo, last_inserted_query, [], opts)
      {:error, _} = err -> err
    end
  end
end
