defmodule Ecto.Adapters.Mysql do
  @moduledoc """
  This is the adapter module for MySQL. It handles and pools the
  connections to the MySQL database with eonblast/emysql.

  ## Options

  The options should be given via `Ecto.Repo.conf/0`.

  `:hostname` - Server hostname;
  `:port` - Server port (default: 5432);
  `:username` - Username;
  `:password` - User password;
  `:size` - The number of connections to keep in the pool;
  `:max_overflow` - The maximum overflow of connections (see poolboy docs);
  `:parameters` - Keyword list of connection parameters;
  `:ssl` - Set to true if ssl should be used (default: false);
  `:ssl_opts` - A list of ssl options, see ssl docs;
  `:lazy` - If false all connections will be started immediately on Repo startup (default: true)
  """

  @behaviour Ecto.Adapter
  @behaviour Ecto.Adapter.Migrations
  @behaviour Ecto.Adapter.Storage

  @default_port 3306
  @timeout 5000

  alias Ecto.Adapters.Mysql.SQL
  alias Ecto.Adapters.Mysql.Worker
  alias Ecto.Associations.Assoc
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util
  alias Ecto.Adapters.Mysql.Result
  alias Ecto.Adapters.Mysql.OkPacket

  ## Adapter API

  @doc false
  defmacro __using__(_opts) do
    quote do
      def __mysql__(:pool_name) do
        __MODULE__.Pool
      end
    end
  end

  @doc false
  def start_link(repo, opts) do
    Worker.start_link(repo.__mysql__(:pool_name), opts)
  end

  @doc false
  def stop(repo) do
    pool_name = repo.__mysql__(:pool_name)
    :emysql.remove_pool(pool_name)
  end

  @doc false
  def all(repo, query, opts) do
    mysql_query = %{query | select: normalize_select(query.select)}

    %Result{rows: rows} = query(repo, SQL.select(mysql_query), [], opts)

    # Transform each row based on select expression
    transformed =
      Enum.map(rows, fn row ->
        values = Tuple.to_list(row)
        transform_row(mysql_query.select.expr, values, mysql_query.sources) |> elem(0)
      end)

    transformed
    |> Ecto.Associations.Assoc.run(query)
    |> preload(repo, query)
  end

  @doc false
  def insert(repo, model, opts) do
    module    = model.__struct__
    returning = module.__schema__(:keywords, model)
      |> Enum.filter.(fn {_, val} -> val == nil end)
      |> Keyword.keys

      case query(repo, SQL.insert(model, returning), [], opts) do
        %Result{rows: [values]} ->
          Enum.zip(returning, Tuple.to_list(values))
        _ ->
          []
      end
  end

  @doc false
  def handle_query(repo, query, opts) do
    %OkPacket{num_rows: nrows} = query(repo, query, [], opts)
    nrows
  end

  @doc false
  def update(repo, model, opts) do
    handle_query(repo, SQL.update(model), opts)
  end

  @doc false
  def update_all(repo, query, values, opts) do
    handle_query(repo, SQL.update_all(query, values), opts)
  end

  @doc false
  def delete(repo, model, opts) do
    handle_query(repo, SQL.delete(model), opts)
  end

  @doc false
  def delete_all(repo, query, opts) do
    handle_query(repo, SQL.delete_all(query), opts)
  end

  @doc """
  Run custom SQL query on given repo.

  ## Options
    `:timeout` - The time in milliseconds to wait for the call to finish,
                 `:infinity` will wait indefinitely (default: 5000);

  ## Examples
      iex> Mysql.query(MyRepo, "SELECT $1 + $2", [40, 2])
  """
  def query(repo, sql, params, opts \\ []) do
    timeout = opts[:timeout] || @timeout
    repo.log({:query, sql}, fn ->
      Worker.query!(repo.__mysql__(:pool_name), sql, params, timeout)
    end)
  end

  @doc false
  def normalize_select(%QueryExpr{expr: {:assoc, _, [_, _]} = assoc} = expr) do
    %{expr | expr: normalize_assoc(assoc)}
  end

  def normalize_select(%QueryExpr{expr: _} = expr), do: expr

  defp normalize_assoc({:assoc, _, [_, _]} = assoc) do
    {var, fields} = Assoc.decompose_assoc(assoc)
    normalize_assoc(var, fields)
  end

  defp normalize_assoc(var, fields) do
    nested = Enum.map(fields, fn {_field, nested} ->
      {var, fields} = Assoc.decompose_assoc(nested)
      normalize_assoc(var, fields)
    end)
    { var, nested }
  end

  ## Result set transformation

  defp transform_row({ :{}, _, list}, values, sources) do
    {result, values } = transform_row(list, values, sources)
    {List.to_tuple(result), values}
  end

  defp transform_row({ :&, _, [_]} = var, values, sources) do
    model = Util.find_source(sources, var) |> Util.model
    model_size = length(model.__schema__(:field_names))
    {model_values, values} = Enum.split(values, model_size)
    if Enum.all?(model_values, &(nil?(&1))) do
      {nil, values}
    else
      {model.__schema__(:allocate, model_values), values }
    end
  end

  # Skip records
  defp transform_row({first, _} = tuple, values, sources) when not is_atom(first) do
    {result, values} = transform_row(Tuple.to_list(tuple), values, sources)
    {List.to_tuple(result), values}
  end

  defp transform_row(list, values, sources) when is_list(list) do
    {result, values} = Enum.reduce(list, {[], values}, fn elem, {res, values} ->
      {result, values} = transform_row(elem, values, sources)
      result = transform_value(result)
      {[result|res], values}
    end)

    {Enum.reverse(result), values} 
  end

  defp transform_row(_, values, _entities) do
    [value|values] = values
    {value, values}
  end

  defp transform_value(:undefined), do: nil

  defp transform_value({:datetime, {{year, mon, day}, {hour, min, sec}}}) do
    Ecto.DateTime[year: year, month: mon, day: day, hour: hour, min: min, sec: sec]
  end

  defp transform_value(value), do: value

  defp preload(results, repo, query) do
    pos = Util.locate_var(query.select.expr, { :&, [], [0] })
    fields = Enum.map(query.preloads, &(&1.expr)) |> Enum.concat
    Ecto.Associations.Preloader.run(results, repo, fields, pos)
  end

  ## Storage API

  @doc false
  def storage_up(opts) do
    # TODO: allow the user to specify those options either in the Repo or on command line
    database_options = ~s(ENCODING='UTF8' LC_COLLATE='en_US.UTF-8' LC_CTYPE='en_US.UTF-8')

    output = run_with_mysql opts, "CREATE DATABASE #{ opts[:database] } " <> database_options

    cond do
      String.length(output) == 0                 -> :ok
      String.contains?(output, "already exists") -> { :error, :already_up }
      true                                       -> { :error, output }
    end
  end

  @doc false
  def storage_down(opts) do
    output = run_with_mysql(opts, "DROP DATABASE #{ opts[:database] }")

    cond do
      String.length(output) == 0                 -> :ok
      String.contains?(output, "does not exist") -> { :error, :already_down }
      true                                       -> { :error, output }
    end
  end

  defp run_with_mysql(database, sql_command) do
    command = ""

    if password = database[:password] do
      command = ~s(MYSQL_PWD=#{ password } )
    end

    if username = database[:username] do
      command = ~s(USER=#{username} ) <> command
    end

    command =
      command <>
      ~s(mysql --silent -u #{ database[:username] } ) <>
      ~s(-h #{ database[:hostname] } ) <>
      ~s(-e "#{ sql_command };" )

    String.to_char_list(command)
    |> :os.cmd
    |> List.to_string
  end

  ## Migration API

  @doc false
  def migrate_up(repo, version, commands) do
    case check_migration_version(repo, version) do
      %Result{rows: []} ->
        Enum.each(commands, &query(repo, &1, []))
        insert_migration_version(repo, version)
        :ok
      _ ->
        :already_up
    end
  end

  @doc false
  def migrate_down(repo, version, commands) do
    case check_migration_version(repo, version) do
      %Result{rows: []} ->
        :missing_up
      _ ->
        Enum.each(commands, &query(repo, &1, []))
        delete_migration_version(repo, version)
        :ok
    end
  end

  @doc false
  def migrated_versions(repo) do
    create_migrations_table(repo)
    %Result{rows: rows} = query(repo, "SELECT version FROM schema_migrations", [])
    List.flatten(rows)
  end

  defp create_migrations_table(repo) do
    query(repo, "CREATE TABLE IF NOT EXISTS schema_migrations (id INT AUTO_INCREMENT, version bigint, PRIMARY KEY(id))", [])
  end

  defp check_migration_version(repo, version) do
    create_migrations_table(repo)
    query(repo, "SELECT version FROM schema_migrations WHERE version = #{version}", [])
  end

  defp insert_migration_version(repo, version) do
    query(repo, "INSERT INTO schema_migrations(version) VALUES (#{version})", [])
  end

  defp delete_migration_version(repo, version) do
    query(repo, "DELETE FROM schema_migrations WHERE version = #{version}", [])
  end
end
