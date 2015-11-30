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

  test "can dump and load the databse structure" do
    {_, 0} = create_database()

    {dump, 0} = Postgres.structure_dump(params())

    {_, 0} = drop_database()

    path = Path.join(tmp_path, "structure.sql")
    File.write!(path, dump)

    {_, 0} = create_empty_database()

    {new_dump, 0} = Postgres.structure_dump(params())
    assert dump != new_dump

    {_, 0} = Postgres.structure_load(params(), path)

    {new_dump, 0} = Postgres.structure_dump(params())
    assert dump == new_dump
  end
end
