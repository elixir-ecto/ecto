defmodule Ecto.Adapters.Postgres do
  @moduledoc """
  Adapter module for PostgreSQL.

  It uses `postgrex` for communicating to the database
  and manages a connection pool with `poolboy`.

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

    * `:encoding` - the database encoding (default: "UTF8")
    * `:template` - the template to create the database from
    * `:lc_collate` - the collation order
    * `:lc_ctype` - the character classification

  """

  use Ecto.Adapters.SQL, :postgrex
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
      run_with_psql opts, "CREATE DATABASE " <> database <>
                          " ENCODING='#{encoding}'" <> extra

    cond do
      status == 0                                -> :ok
      String.contains?(output, "already exists") -> {:error, :already_up}
      true                                       -> {:error, output}
    end
  end

  @doc false
  def storage_down(opts) do
    {output, status} = run_with_psql(opts, "DROP DATABASE #{opts[:database]}")

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

    args = args ++ ["--quiet", "--host", database[:hostname], "-d", "template1", "-c", sql_command]
    System.cmd("psql", args, env: env, stderr_to_stdout: true)
  end
end
