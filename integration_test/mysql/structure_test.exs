Code.require_file "../support/file_helpers.exs", __DIR__

defmodule Ecto.Integration.StructureTest do
  use ExUnit.Case

  import Support.FileHelpers

  alias Ecto.Adapters.MySQL

  def params do
    Ecto.Repo.Supervisor.parse_url(
      Application.get_env(:ecto, :mysql_test_url) <> "/structure_mgt"
    )
  end

  def drop_database do
    run_mysql("DROP DATABASE #{params[:database]};")
  end

  def create_database do
    create_empty_database()
    run_mysql("CREATE TABLE posts (title varchar(20));", ["-D", params[:database]])
  end

  def create_empty_database do
    run_mysql("CREATE DATABASE #{params[:database]};")
  end

  def run_mysql(sql, args \\ []) do
    args = ["-u", params[:username], "-e", sql | args]
    System.cmd "mysql", args
  end

  setup do
    on_exit fn -> drop_database end
    :ok
  end

  test "can dump and load structure" do
    create_database()

    # Default path
    {:ok, _} = MySQL.structure_dump(tmp_path, params())
    dump = File.read!(Path.join(tmp_path, "structure.sql"))

    drop_database()
    create_empty_database()

    # Load custom
    dump_path = Path.join(tmp_path, "custom.sql")
    File.rm(dump_path)
    {:error, _} = MySQL.structure_load(tmp_path, [dump_path: dump_path] ++ params())

    # Dump custom
    {:ok, _} = MySQL.structure_dump(tmp_path, [dump_path: dump_path] ++ params())
    assert strip_timestamp(dump) != strip_timestamp(File.read!(dump_path))

    # Load original
    {:ok, _} = MySQL.structure_load(tmp_path, params())

    {:ok, _} = MySQL.structure_dump(tmp_path, [dump_path: dump_path] ++ params())
    assert strip_timestamp(dump) == strip_timestamp(File.read!(dump_path))
  end

  defp strip_timestamp(dump) do
    dump
    |> String.split("\n")
    |> Enum.reject(&String.contains?(&1, "completed on"))
    |> Enum.join("\n")
  end
end
