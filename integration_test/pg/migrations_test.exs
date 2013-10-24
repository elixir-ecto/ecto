defmodule Ecto.Integration.MigrationsTest do
  use Ecto.Integration.Postgres.Case

  defmodule GoodMigration do
    use Ecto.Migration

    def up do
      "CREATE TABLE migrations_test(id serial primary key, name varchar(25))"
    end

    def down do
      "DROP table migrations_test"
    end
  end

  defmodule BadMigration do
    use Ecto.Migration

    def up do
      "CREATE WHAT"
    end

    def down do
      "DROP table migrations_test"
    end
  end

  import Ecto.Migrator

  test "migrations up and down" do
    assert migrated_versions(TestRepo) == { :ok, [] }
    assert up(TestRepo, 20080906120000, GoodMigration) == :ok
    assert migrated_versions(TestRepo) == { :ok, [20080906120000] }
    assert up(TestRepo, 20080906120000, GoodMigration) == :already_up
    assert migrated_versions(TestRepo) == { :ok, [20080906120000] }
    assert down(TestRepo, 20080906120001, GoodMigration) == :missing_up
    assert migrated_versions(TestRepo) == { :ok, [20080906120000] }
    assert down(TestRepo, 20080906120000, GoodMigration) == :ok
    assert migrated_versions(TestRepo) == { :ok, [] }
  end

  # test "bad migration" do
  #   assert { :error, _ } = up(TestRepo, 20080906120000, BadMigration)
  # end

  defp migrated_versions(repo) do
    repo.adapter.migrated_versions(repo)
  end
end
