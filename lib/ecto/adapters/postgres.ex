defmodule Ecto.Adapters.Postgres do
  @moduledoc """
  Adapter module for PostgreSQL.

  It handles and pools the connections to the postgres
  database using `postgrex` with `poolboy`.

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

  use Ecto.Adapters.SQL, :postgrex
  @behaviour Ecto.Adapter.Storage

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
    env = []

    if password = database[:password] do
      env = [{"PGPASSWORD", password}|env]
    end

    if username = database[:username] do
      env = [{"PGUSER", username}|env]
    end

    if port = database[:port] do
      env = [{"PGPORT", to_string(port)}|env]
    end

    args = ["--quiet", "template1", "--host", database[:hostname], "-c", sql_command]
    System.cmd("psql", args, env: env, stderr_to_stdout: true) |> elem(0)
  end
end
