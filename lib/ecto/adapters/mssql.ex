defmodule Ecto.Adapters.Mssql do
  
  @moduledoc """
  Adapter module for MSSQL.

  It uses `tds` for communicating to the database
  and manages a connection pool with `poolboy`.

  ## Features

    * Full query support (including joins, preloads and associations)
    * Support for transactions
    * Support for data migrations
    * Support for ecto.create and ecto.drop operations
    * Support for transactional tests via `Ecto.Adapters.SQL`

  ## Options

  Mssql options split in different categories described
  below. All options should be given via the repository
  configuration.

  ### Connection options

    * `:hostname` - Server hostname
    * `:port` - Server port (default: 1433)
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
  alias Tds
  use Ecto.Adapters.SQL, :tds
  @behaviour Ecto.Adapter.Storage

  def storage_up(opts) do
    database = Keyword.fetch!(opts, :database)

    extra = ""

    if lc_collate = Keyword.get(opts, :lc_collate) do
      extra = extra <> " COLLATE='#{lc_collate}'"
    end

    {output, status} =
      run_with_sql_conn opts, "CREATE DATABASE " <> database <> extra
    #IO.inspect status
    cond do
      status == 0                                -> :ok
      output != nil -> if String.contains?(output[:msg_text], "already exists"), do: {:error, :already_up}
      true                                       -> {:error, output}
    end
  end

  @doc false
  def storage_down(opts) do
    {output, status} = run_with_sql_conn(opts, "DROP DATABASE #{opts[:database]}")
    IO.inspect output
    cond do
      status == 0                                -> :ok
      output != nil -> if String.contains?(output[:msg_text], "does not exist"), do: {:error, :already_down}
      true                                       -> {:error, output}
    end
  end

  defp run_with_sql_conn(opts, sql_command) do
    opts = opts |> Keyword.put(:database, "master")
    case Ecto.Adapters.Mssql.Connection.connect(opts) do
      {:ok, pid} ->
        # Execute the query
        case Ecto.Adapters.Mssql.Connection.query(pid, sql_command, [], []) do
          {:ok, %{}} -> {:ok, 0}
          {_, %Tds.Error{message: message, mssql: error}} ->
            {error, 1}
        end
      {_,error} -> 
        {error, 1}
    end
  end

  def supports_ddl_transaction? do
    true
  end
end