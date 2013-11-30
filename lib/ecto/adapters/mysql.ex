defmodule Ecto.Adapters.Mysql do
  @moduledoc false

  @behaviour Ecto.Adapter
  @default_port 3306

  alias Ecto.Adapters.Mysql.SQL
  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util
  alias Ecto.Query.Normalizer

  defmacro __using__(_opts) do
    quote do
      def __mysql__(:conn_name) do
        __MODULE__.Conn
      end
    end
  end

  @doc false
  def start(repo) do
    prepare_start(repo)
  end

  def all(repo, Query[] = query) do
    sql = SQL.select(query)
    result = execute(repo, sql)

    case elem(result, 0) do
      :result_packet ->
        transformed = Enum.map(elem(result, 3), fn row ->
          QueryExpr[expr: expr] = Normalizer.normalize_select(query.select)
          transform_row(expr, row, query.models)
        end)

        { :ok, transformed }
      :error_packet -> { :error, result }
    end
  end

  def create(repo, entity) do
    sql = SQL.insert(entity)
    result = execute(repo, sql)

    case elem(result, 0) do
      :ok_packet -> { :ok, elem(result, 3) }
      :error_packet -> { :error, result }
    end
  end

  def update(repo, entity) do
    sql = SQL.update(entity)
    result = execute(repo, sql)

    case elem(result, 0) do
      :ok_packet -> { :ok, elem(result, 2) }
      :error_packet -> { :error, result }
    end
  end

  def update_all(repo, query, values) do
    sql = SQL.update_all(query, values)
    result = execute(repo, sql)

    case elem(result, 0) do
      :ok_packet -> { :ok, elem(result, 2) }
      :error_packet -> { :error, result }
    end
  end

  def delete(repo, entity) do
    sql = SQL.delete(entity)
    result = execute(repo, sql)

    case elem(result, 0) do
      :ok_packet -> { :ok, elem(result, 2) }
      :error_packet -> { :error, result }
    end
  end

  def delete_all(repo, query) do
    sql = SQL.delete_all(query)
    result = execute(repo, sql)

    case elem(result, 0) do
      :ok_packet -> { :ok, elem(result, 2) }
      :error_packet -> { :error, result }
    end
  end

  @doc false
  def transaction_begin(repo) do
    result = execute(repo, "START TRANSACTION")
    case elem(result, 0) do
      :ok_packet -> :ok
      _ -> result
    end
  end

  @doc false
  def transaction_rollback(repo) do
    result = execute(repo, "ROLLBACK")
    case elem(result, 0) do
      :ok_packet -> :ok
      _ -> result
    end
  end

  @doc false
  def transaction_commit(repo) do
    result = execute(repo, "COMMIT")
    case elem(result, 0) do
      :ok_packet -> :ok
      _ -> result
    end
  end

  defp transform_row({ :&, _, [_] } = var, row, models) do
    model = Util.find_model(models, var)
    entity = model.__ecto__(:entity)
    values = Enum.map(row, &transform_value(&1))
    entity.__ecto__(:allocate, values)
  end

  defp transform_row({ _, _ } = tuple, row, models) do
    result = transform_row(tuple_to_list(tuple), row, models)
    list_to_tuple(result)
  end

  defp transform_row(_, row, _) do
    if length(row) == 1 do
      Enum.first(row)
    else
      Enum.map(row, &transform_value(&1))
    end
  end

  defp transform_value(:undefined), do: nil
  defp transform_value(value) when is_list(value), do: String.from_char_list!(value)
  defp transform_value({:datetime, {date, time}}) do
    Ecto.DateTime.new(year: elem(date,0), month: elem(date,1), day: elem(date,2),
                      hour: elem(time,0), min: elem(time,1), sec: elem(time,2))
  end
  defp transform_value(value), do: value

  defp prepare_start(repo) do
    safe_start(:crypto)
    safe_start(:emysql)

    opts = Ecto.Repo.parse_url(repo.url, @default_port)
    worker_opts = fix_worker_opts(opts)

    :emysql.add_pool(repo.__mysql__(:conn_name), 1, worker_opts[:username], worker_opts[:password], worker_opts[:hostname], worker_opts[:port], worker_opts[:database], :utf8)
  end

  defp fix_worker_opts(opts) do
    Enum.map(opts, fn
      { :username, v } -> { :username, String.to_char_list!(v) }
      { :password, v } -> { :password, String.to_char_list!(v) }
      { :hostname, v } -> { :hostname, String.to_char_list!(v) }
      { :database, v } -> { :database, String.to_char_list!(v) }
      rest -> rest
    end)
  end

  defp safe_start(application) do
    case :application.start(application) do
      :ok -> :ok
      { :error, { :already_started, _ } } -> :ok
      { :error, reason } ->
        raise "could not start #{application} application, reason: #{inspect reason}"
    end
  end

  defp execute(repo, statement) do
    :emysql.execute(repo.__mysql__(:conn_name), statement)
  end
end
