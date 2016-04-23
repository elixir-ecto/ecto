Code.require_file "../support/file_helpers.exs", __DIR__

defmodule Ecto.Integration.StructureTest do
  use ExUnit.Case

  import Support.FileHelpers

  alias Ecto.Adapters.Postgres

  def params do
    Ecto.Repo.Supervisor.parse_url(
      Application.get_env(:ecto, :pg_test_url) <> "/structure_mgt"
    )
  end

  def drop_database do
    run_psql("DROP DATABASE #{params[:database]};")
  end

  def create_database do
    create_empty_database()
    run_psql("CREATE TABLE posts (title varchar(20));", [params[:database]])
  end

  def create_empty_database do
    run_psql("CREATE DATABASE #{params[:database]};")
  end

  def run_psql(sql, args \\ []) do
    args = ["-U", params[:username], "-c", sql | args]
    System.cmd "psql", args
  end

  setup do
    on_exit fn -> drop_database end
    :ok
  end

  test "can dump and load structure" do
    create_database()

    # Default path
    :ok = Postgres.structure_dump(tmp_path, params())
    dump = File.read!(Path.join(tmp_path, "structure.sql"))

    drop_database()
    create_empty_database()

    # Load custom
    dump_path = Path.join(tmp_path, "custom.sql")
    File.rm(dump_path)
    {:error, _} = Postgres.structure_load(tmp_path, [dump_path: dump_path] ++ params())

    # Dump custom
    :ok = Postgres.structure_dump(tmp_path, [dump_path: dump_path] ++ params())
    assert dump != File.read!(dump_path)

    # Load original
    :ok = Postgres.structure_load(tmp_path, params())

    :ok = Postgres.structure_dump(tmp_path, [dump_path: dump_path] ++ params())
    assert dump == File.read!(dump_path)
  end
end
