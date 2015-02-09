if Code.ensure_loaded?(Mariaex.Connection) do

  defmodule Ecto.Adapters.MySQL.Connection do
    @moduledoc false

    @default_port 3306
    @behaviour Ecto.Adapters.SQL.Connection

    ## Connection

    def connect(opts) do
      opts = Keyword.put_new(opts, :port, @default_port)
      Mariaex.Connection.start_link(opts)
    end

    def disconnect(conn) do
      try do
        Mariaex.Connection.stop(conn)
      catch
        :exit, {:noproc, _} -> :ok
      end
      :ok
    end

    def query(conn, sql, params, opts \\ []) do
      case Mariaex.Connection.query(conn, sql, params, opts) do
        {:ok, %Mariaex.Result{} = result} -> {:ok, Map.from_struct(result)}
        {:error, %Mariaex.Error{} = err} -> err
      end
    end

    ## Transaction

    def begin_transaction do
      "BEGIN"
    end

    def rollback do
      "ROLLBACK"
    end

    def commit do
      "COMMIT"
    end

    def savepoint(savepoint) do
      "SAVEPOINT " <> savepoint
    end

    def rollback_to_savepoint(savepoint) do
      "ROLLBACK TO SAVEPOINT " <> savepoint
    end

    ## DDL

    alias Ecto.Migration.Table

    def ddl_exists(%Table{name: name}) do
      """
      SELECT COUNT (1) information_schema.tables C
       WHERE t.table_schema = SCHEMA()
             AND t.table_name = '#{escape_string(to_string(name))}'
      """
    end

    ## Helpers

    defp escape_string(value) when is_binary(value) do
      :binary.replace(value, "'", "''", [:global])
    end
  end
end
