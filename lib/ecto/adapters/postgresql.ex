defmodule Ecto.Adapters.Postgresql do
  @behaviour Ecto.Adapter

  @default_port 5432

  defmacro __using__(_opts) do
    quote do
      def __postgres__(:pool_name) do
        unquote(Module.concat(__MODULE__, Pool))
      end
    end
  end

  def start(repo) do
    case :application.ensure_started(:pgsql) do
      :ok -> :ok
      { :error, reason } ->
        raise "could not start :pgsql application, reason: #{inspect reason}"
    end

    pool_name = repo.__postgres__(:pool_name)
    opts      = Ecto.Repo.parse_url(repo.url, @default_port)

    { pool_opts, worker_opts } = Dict.split(opts, [:size, :max_overflow])
    pool_opts = pool_opts ++ [
      name: { :local, pool_name },
      worker_module: :pgsql_connection ]
    worker_opts = fix_worker_opts(worker_opts)

    Ecto.PoolSup.start_child([pool_opts, worker_opts])
  end

  def fetch(repo, sql) when is_binary(sql) do
    result = transaction(repo, fn(conn) ->
      :pgsql_connection.simple_query(sql, { :pgsql_connection, conn })
    end)

    case result do
      { { :select, _nrows }, rows } ->
        rows
      { :error, _ } = err ->
        err
    end
  end

  def fetch(repo, Ecto.Query.Query[] = query) do
    sql = Ecto.SQL.compile(query)
    fetch(repo, sql)
  end

  defp transaction(repo, fun) do
    :poolboy.transaction(repo.__postgres__(:pool_name), fun)
  end

  defp fix_worker_opts(opts) do
    Enum.map(opts, fn
      { :username, v } -> { :user, v }
      { :hostname, v } -> { :host, binary_to_list(v) }
      rest -> rest
    end)
  end
end
