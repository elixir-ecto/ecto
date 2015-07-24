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
  configuration.

  ### Compile time options

  Those options should be set in the config file and require
  recompilation in order to make an effect.

    * `:adapter` - The adapter name, in this case, `Ecto.Adapters.Postgres`
    * `:name`- The name of the Repo supervisor process
    * `:pool` - The connection pool module, defaults to `Ecto.Pools.Poolboy`
    * `:timeout` - The default timeout to use on queries, defaults to `5000`
    * `:log_level` - The level to use when logging queries (default: `:debug`)

  ### Connection options

    * `:hostname` - Server hostname
    * `:port` - Server port (default: 5432)
    * `:username` - Username
    * `:password` - User password
    * `:parameters` - Keyword list of connection parameters
    * `:ssl` - Set to true if ssl should be used (default: false)
    * `:ssl_opts` - A list of ssl options, see Erlang's `ssl` docs
    * `:connect_timeout` - The timeout for establishing new connections (default: 5000)
    * `:extensions` - Specify extensions to the postgres adapter

  ### Storage options

    * `:encoding` - the database encoding (default: "UTF8")
    * `:template` - the template to create the database from
    * `:lc_collate` - the collation order
    * `:lc_ctype` - the character classification

  """

  # Inherit all behaviour from Ecto.Adapters.SQL
  use Ecto.Adapters.SQL, :postgrex

  # And provide a custom storage implementation
  @behaviour Ecto.Adapter.Storage

  ## Storage API

  @doc false
  def storage_up(opts) do
    database = Keyword.fetch!(opts, :database)
    encoding = Keyword.get(opts, :encoding, "UTF8")

    extra = ""

    if template = Keyword.get(opts, :template) do
      extra = extra <> " TEMPLATE=#{template}"
    end

    if lc_collate = Keyword.get(opts, :lc_collate) do
      extra = extra <> " LC_COLLATE='#{lc_collate}'"
    end

    if lc_ctype = Keyword.get(opts, :lc_ctype) do
      extra = extra <> " LC_CTYPE='#{lc_ctype}'"
    end

    {output, status} =
      run_with_psql opts, "CREATE DATABASE \"" <> database <>
                          "\" ENCODING='#{encoding}'" <> extra

    cond do
      status == 0                                -> :ok
      String.contains?(output, "already exists") -> {:error, :already_up}
      true                                       -> {:error, output}
    end
  end

  @doc false
  def storage_down(opts) do
    {output, status} = run_with_psql(opts, "DROP DATABASE \"#{opts[:database]}\"")

    cond do
      status == 0                                -> :ok
      String.contains?(output, "does not exist") -> {:error, :already_down}
      true                                       -> {:error, output}
    end
  end

  defp run_with_psql(database, sql_command) do
    unless System.find_executable("psql") do
      raise "could not find executable `psql` in path, " <>
            "please guarantee it is available before running ecto commands"
    end

    env =
      if password = database[:password] do
        [{"PGPASSWORD", password}]
      else
        []
      end

    args = []

    if username = database[:username] do
      args = ["-U", username|args]
    end

    if port = database[:port] do
      args = ["-p", to_string(port)|args]
    end

    host = database[:hostname] || System.get_env("PGHOST") || "localhost"
    args = args ++ ["--quiet", "--host", host, "--set", "ON_ERROR_STOP=1", "--no-psqlrc", "-d", "template1", "-c", sql_command]
    System.cmd("psql", args, env: env, stderr_to_stdout: true)
  end

  @doc false

  def supports_ddl_transaction? do
    true
  end
end
