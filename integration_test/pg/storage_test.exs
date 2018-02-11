Code.require_file "../support/file_helpers.exs", __DIR__

defmodule Ecto.Integration.StorageTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  import Support.FileHelpers
  alias Ecto.Adapters.Postgres
  alias Ecto.Integration.TestRepo

  def params do
    # Pass log false to ensure we can still create/drop.
    url = Application.get_env(:ecto, :pg_test_url) <> "/storage_mgt"
    [log: false] ++ Ecto.Repo.Supervisor.parse_url(url)
  end

  def wrong_params do
    Keyword.merge params(),
      [username: "randomuser",
       password: "password1234"]
  end

  def drop_database do
    run_psql("DROP DATABASE #{params()[:database]};")
  end

  def create_database do
    run_psql("CREATE DATABASE #{params()[:database]};")
  end

  def create_posts do
    run_psql("CREATE TABLE posts (title varchar(20));", [params()[:database]])
  end

  def run_psql(sql, args \\ []) do
    args = ["-U", params()[:username], "-c", sql | args]
    System.cmd "psql", args
  end

  test "storage up (twice in a row)" do
    assert Postgres.storage_up(params()) == :ok
    assert Postgres.storage_up(params()) == {:error, :already_up}
  after
    drop_database()
  end

  test "storage down (twice in a row)" do
    create_database()
    assert Postgres.storage_down(params()) == :ok
    assert Postgres.storage_down(params()) == {:error, :already_down}
  end

  test "storage up and down (wrong credentials)" do
    refute Postgres.storage_up(wrong_params()) == :ok
    create_database()
    refute Postgres.storage_down(wrong_params()) == :ok
  after
    drop_database()
  end

  test "structure dump and load" do
    create_database()
    create_posts()

    # Default path
    {:ok, _} = Postgres.structure_dump(tmp_path(), params())
    dump = File.read!(Path.join(tmp_path(), "structure.sql"))

    drop_database()
    create_database()

    # Load custom
    dump_path = Path.join(tmp_path(), "custom.sql")
    File.rm(dump_path)
    {:error, _} = Postgres.structure_load(tmp_path(), [dump_path: dump_path] ++ params())

    # Dump custom
    {:ok, _} = Postgres.structure_dump(tmp_path(), [dump_path: dump_path] ++ params())
    assert dump != File.read!(dump_path)

    # Load original
    {:ok, _} = Postgres.structure_load(tmp_path(), params())

    {:ok, _} = Postgres.structure_dump(tmp_path(), [dump_path: dump_path] ++ params())
    assert dump == File.read!(dump_path)
  after
    drop_database()
  end

  test "structure dump and load with migrations table" do
    {:ok, path} = Postgres.structure_dump(tmp_path(), TestRepo.config())
    contents = File.read!(path)
    assert contents =~ ~s[INSERT INTO public."schema_migrations" (version) VALUES (0)]
  end
end
