defmodule Ecto.Integration.StorageTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.Mssql

  def correct_params do
    [database: "storage_mgt",
     username: "mssql",
     password: "mssql",
     hostname: "mssql.local"]
  end

  def wrong_user do
    [database: "storage_mgt",
     username: "randomuser",
     password: "password1234",
     hostname: "mssql.local"]
  end

  def drop_database do
    run_with_sql_conn(correct_params, "DROP DATABASE storage_mgt")
  end

  def create_database do
    run_with_sql_conn(correct_params, "CREATE DATABASE storage_mgt")
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
      {_, error} -> 
        {error, 1}
    end
  end

  setup do
    on_exit fn -> drop_database end
    :ok
  end
  
  # test "storage up (twice in a row)" do
  #   assert Mssql.storage_up(correct_params) == :ok
  #   assert Mssql.storage_up(correct_params) == {:error, :already_up}
  # end

  # test "storage up (wrong credentials)" do
  #   refute Mssql.storage_up(wrong_user) == :ok
  # end

  # test "storage down (twice in a row)" do
  #   create_database
  #   assert Mssql.storage_down(correct_params) == :ok
  #   assert Mssql.storage_down(correct_params) == {:error, :already_down}
  # end

  # test "storage down (wrong credentials)" do
  #   create_database
  #   refute Mssql.storage_down(wrong_user) == :ok
  # end
end
