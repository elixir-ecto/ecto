defmodule Ecto.Adapters.MySQL do
  @moduledoc """
  Adapter module for MySQL.

  It handles and pools the connections to the MySQL
  database using `mariaex` with `poolboy`.

  ## Options


  Mariaex options split in different categories described
  below. All options should be given via the repository
  configuration.

  ### Connection options

  * `:hostname` - Server hostname;
  * `:port` - Server port (default: 5432);
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

    output =
      run_with_mysql opts, "CREATE DATABASE " <> database <>
                           " DEFAULT CHARACTER SET = #{charset} " <> extra

    cond do
      String.length(output) == 0                  -> :ok
      String.contains?(output, "database exists") -> {:error, :already_up}
      true                                        -> {:error, output}
    end
  end


  @doc false
  def storage_down(opts) do
    output = run_with_mysql(opts, "DROP DATABASE #{opts[:database]}")

    cond do
      String.length(output) == 0                 -> :ok
      String.contains?(output, "doesn't exist") -> {:error, :already_down}
      true                                       -> {:error, output}
    end
  end

  defp run_with_mysql(database, sql_command) do
    env = []
    
    if password = database[:password] do
      env = [{"MYSQL_PWD", password}|env]
    end

    if port = database[:port] do
      env = [{"MYSQL_TCP_PORT", port}|env]
    end

    args = ["--silent", "-u", database[:username], "-h", database[:hostname], "-e", sql_command]
    System.cmd("mysql", args, env: env, stderr_to_stdout: true) |> elem(0)
  end
end
