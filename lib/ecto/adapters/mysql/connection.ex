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
        {:error, %Mariaex.Error{}} =  err -> err
        :ok -> {:ok, %{}}
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
    alias Ecto.Migration.Index
    alias Ecto.Migration.Reference

    def ddl_exists(%Table{name: name}) do
      """
      SELECT COUNT(1)
        FROM information_schema.tables T
       WHERE t.table_schema = SCHEMA()
             AND t.table_name = '#{escape_string(to_string(name))}'
      """
    end

    def execute_ddl({:create, %Table{} = table, columns}) do
      "CREATE TABLE #{table.name} (#{column_definitions(columns)})"
    end

    defp column_definitions(columns) do
      Enum.map_join(columns, ", ", &column_definition/1)
    end

    defp column_definition({:add, name, type, opts}) do
      assemble([name, column_type(type, opts), column_options(name, opts)])
    end

    defp column_options(name, opts) do
      default = Keyword.get(opts, :default)
      null    = Keyword.get(opts, :null)
      pk      = Keyword.get(opts, :primary_key)

      [default_expr(default), null_expr(null), pk_expr(pk, name)]
    end

    defp pk_expr(true, name), do: ", PRIMARY KEY(#{name})"
    defp pk_expr(_, _), do: nil

    defp null_expr(false), do: "NOT NULL"
    defp null_expr(true), do: "NULL"
    defp null_expr(_), do: nil

    defp default_expr(nil),
      do: nil
    defp default_expr(literal) when is_binary(literal),
      do: "DEFAULT '#{escape_string(literal)}'"
    defp default_expr(literal) when is_number(literal) or is_boolean(literal),
      do: "DEFAULT #{literal}" # TODO: Check the boolean here :P
    defp default_expr({:fragment, expr}),
      do: "DEFAULT #{expr}"

    defp column_type(%Reference{} = ref, opts) do
      "#{column_type(ref.type, opts)} REFERENCES #{quote_name(ref.table)}(#{quote_name(ref.column)})"
    end

    defp column_type(type, opts) do
      size      = Keyword.get(opts, :size)
      precision = Keyword.get(opts, :precision)
      scale     = Keyword.get(opts, :scale)
      type_name = ecto_to_db(type)

      cond do
        size            -> "#{type_name}(#{size})"
        precision       -> "#{type_name}(#{precision},#{scale || 0})"
        type == :string -> "#{type_name}(255)"
        true            -> "#{type_name}"
      end
    end

    ## Helpers

    defp quote_name(name), do: "\"#{name}\""

    defp assemble(list) do
      list
      |> List.flatten
      |> Enum.filter(&(&1 != nil))
      |> Enum.join(" ")
    end

    defp escape_string(value) when is_binary(value) do
      :binary.replace(value, "'", "''", [:global])
    end

    defp ecto_to_db(:string),     do: "varchar"
    defp ecto_to_db(:datetime),   do: "timestamp"
    defp ecto_to_db(:binary),     do: "blob"
    defp ecto_to_db(other),       do: Atom.to_string(other)
  end
end
