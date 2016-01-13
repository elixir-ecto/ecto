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
    * `:pool_timeout` - The default timeout to use on pool calls, defaults to `5000`
    * `:timeout` - The default timeout to use on queries, defaults to `15000`
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
    * `:after_connect` - A `{mod, fun, args}` to be invoked after a connection is established

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

    command = "CREATE DATABASE \"#{database}\" " <>
              "ENCODING '#{encoding}'" <> extra

    case run_query(opts, command) do
      :ok ->
        :ok
      {:error, %Postgrex.Error{message: nil, postgres: %{code: :duplicate_database}}} ->
        :already_up
      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  @doc false
  def storage_down(opts) do
    database = Keyword.fetch!(opts, :database)
    command = "DROP DATABASE \"#{database}\""

    case run_query(opts, command) do
      :ok ->
        :ok
      {:error, %Postgrex.Error{message: nil, postgres: %{code: :invalid_catalog_name}}} ->
        :already_down
      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  defp run_query(opts, sql) do
    opts =
      opts
      |> Keyword.delete(:name)
      |> Keyword.put(:database, "template1")
      |> Keyword.put(:pool, DBConnection.Connection)
      |> Keyword.put(:backoff_type, :stop)

    {:ok, pid} = Task.Supervisor.start_link

    task = Task.Supervisor.async_nolink(pid, fn ->
      {:ok, conn} = Postgrex.start_link(opts)

      value = Ecto.Adapters.Postgres.Connection.query(conn, sql, [], opts)
      GenServer.stop(conn)
      value
    end)

    timeout = Keyword.get(opts, :timeout, 15_000)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, _}} ->
        :ok
      {:ok, {:error, error}} ->
        {:error, error}
      {:exit, {%Postgrex.Error{} = error, _}} ->
        {:error, error}
      {:exit, {%DBConnection.Error{} = error, _}} ->
        {:error, error}
      {:exit, reason}  ->
        {:error, RuntimeError.exception(Exception.format_exit(reason))}
      nil ->
        {:error, RuntimeError.exception("command timed out")}
    end
  end

  @doc false
  def supports_ddl_transaction? do
    true
  end
end
