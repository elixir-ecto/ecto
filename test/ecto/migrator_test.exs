defmodule Ecto.MigratorTest do
  use ExUnit.Case

  import Support.FileHelpers
  import Ecto.Migrator
  alias Ecto.TestRepo
  alias Ecto.Migration.SchemaMigration

  defmodule Migration do
    use Ecto.Migration

    def up do
      execute "up"
    end

    def down do
      execute "down"
    end
  end

  defmodule ChangeMigration do
    use Ecto.Migration

    def change do
      create table(:posts) do
        add :name, :string
      end

      create index(:posts, [:title])
    end
  end

  defmodule ChangeMigrationPrefix do
    use Ecto.Migration

    def change do
      create table(:comments, prefix: :foo) do
        add :name, :string
      end

      create index(:posts, [:title], prefix: :foo)
    end
  end

  defmodule UpDownMigration do
    use Ecto.Migration

    def up do
      alter table(:posts) do
        add :name, :string
      end
    end

    def down do
      execute "foo"
    end
  end

  defmodule NoTransactionMigration do
    use Ecto.Migration
    @disable_ddl_transaction true

    def change do
      create index(:posts, [:foo])
    end
  end

  defmodule InvalidMigration do
    use Ecto.Migration
  end


  defmodule TestSchemaRepo do
    use Ecto.Repo, otp_app: :ecto, adapter: Ecto.TestAdapter
  end

  Application.put_env(:ecto, TestSchemaRepo, [migration_table: "my_schema_migrations"])

  setup do
    Process.put(:migrated_versions, [1, 2, 3])
    :ok
  end

  test "custom schema migrations table is right" do
    assert SchemaMigration.get_table_name(TestRepo) == "schema_migrations"
    assert SchemaMigration.get_table_name(TestSchemaRepo) == "my_schema_migrations"
  end

  test "logs migrations" do
    output = capture_log fn ->
      :ok = up(TestRepo, 0, ChangeMigration)
    end

    assert output =~ "== Running Ecto.MigratorTest.ChangeMigration.change/0 forward"
    assert output =~ "create table posts"
    assert output =~ "create index posts_title_index"
    assert output =~ ~r"== Migrated in \d.\ds"

    output = capture_log fn ->
      :ok = down(TestRepo, 0, ChangeMigration)
    end

    assert output =~ "== Running Ecto.MigratorTest.ChangeMigration.change/0 backward"
    assert output =~ "drop table posts"
    assert output =~ "drop index posts_title_index"
    assert output =~ ~r"== Migrated in \d.\ds"

    output = capture_log fn ->
      :ok = up(TestRepo, 0, ChangeMigrationPrefix)
    end

    assert output =~ "== Running Ecto.MigratorTest.ChangeMigrationPrefix.change/0 forward"
    assert output =~ "create table foo.comments"
    assert output =~ "create index foo.posts_title_index"
    assert output =~ ~r"== Migrated in \d.\ds"

    output = capture_log fn ->
      :ok = down(TestRepo, 0, ChangeMigrationPrefix)
    end

    assert output =~ "== Running Ecto.MigratorTest.ChangeMigrationPrefix.change/0 backward"
    assert output =~ "drop table foo.comments"
    assert output =~ "drop index foo.posts_title_index"
    assert output =~ ~r"== Migrated in \d.\ds"

    output = capture_log fn ->
      :ok = up(TestRepo, 0, UpDownMigration)
    end

    assert output =~ "== Running Ecto.MigratorTest.UpDownMigration.up/0 forward"
    assert output =~ "alter table posts"
    assert output =~ ~r"== Migrated in \d.\ds"

    output = capture_log fn ->
      :ok = down(TestRepo, 0, UpDownMigration)
    end

    assert output =~ "== Running Ecto.MigratorTest.UpDownMigration.down/0 forward"
    assert output =~ "execute \"foo\""
    assert output =~ ~r"== Migrated in \d.\ds"
  end

  test "up invokes the repository adapter with up commands" do
    assert up(TestRepo, 0, Migration, log: false) == :ok
    assert up(TestRepo, 1, Migration, log: false) == :already_up
    assert up(TestRepo, 10, ChangeMigration, log: false) == :ok
  end

  test "down invokes the repository adapter with down commands" do
    assert down(TestRepo, 0, Migration, log: false) == :already_down
    assert down(TestRepo, 1, Migration, log: false) == :ok
    assert down(TestRepo, 2, ChangeMigration, log: false) == :ok
  end

  test "up raises error when missing up/0 and change/0" do
    assert_raise Ecto.MigrationError, fn ->
      Ecto.Migrator.up(TestRepo, 0, InvalidMigration, log: false)
    end
  end

  test "down raises error when missing down/0 and change/0" do
    assert_raise Ecto.MigrationError, fn ->
      Ecto.Migrator.down(TestRepo, 1, InvalidMigration, log: false)
    end
  end

  test "expects files starting with an integer" do
    in_tmp fn path ->
      create_migration "a_sample.exs"
      assert run(TestRepo, path, :up, all: true, log: false) == []
    end
  end

  test "fails if there is no migration in file" do
    in_tmp fn path ->
      File.write! "13_sample.exs", ":ok"
      assert_raise Ecto.MigrationError, "file 13_sample.exs does not contain any Ecto.Migration", fn ->
        run(TestRepo, path, :up, all: true, log: false)
      end
    end
  end

  test "fails if there are duplicated versions" do
    in_tmp fn path ->
      create_migration "13_hello.exs"
      create_migration "13_other.exs"
      assert_raise Ecto.MigrationError, "migrations can't be executed, migration version 13 is duplicated", fn ->
        run(TestRepo, path, :up, all: true, log: false)
      end
    end
  end

  test "fails if there are duplicated name" do
    in_tmp fn path ->
      create_migration "13_hello.exs"
      create_migration "14_hello.exs"
      assert_raise Ecto.MigrationError, "migrations can't be executed, migration name hello is duplicated", fn ->
        run(TestRepo, path, :up, all: true, log: false)
      end
    end
  end

  test "upwards migrations skips migrations that are already up" do
    in_tmp fn path ->
      create_migration "1_sample.exs"
      assert run(TestRepo, path, :up, all: true, log: false) == []
    end
  end

  test "downwards migrations skips migrations that are already down" do
    in_tmp fn path ->
      create_migration "1_sample1.exs"
      create_migration "4_sample2.exs"
      assert run(TestRepo, path, :down, all: true, log: false) == [1]
    end
  end

  test "stepwise migrations stop before all have been run" do
    in_tmp fn path ->
      create_migration "13_step_premature_end1.exs"
      create_migration "14_step_premature_end2.exs"
      assert run(TestRepo, path, :up, step: 1, log: false) == [13]
    end
  end

  test "stepwise migrations stop at the number of available migrations" do
    in_tmp fn path ->
      create_migration "13_step_to_the_end1.exs"
      create_migration "14_step_to_the_end2.exs"
      assert run(TestRepo, path, :up, step: 2, log: false) == [13, 14]
    end
  end

  test "stepwise migrations stop even if asked to exceed available" do
    in_tmp fn path ->
      create_migration "13_step_past_the_end1.exs"
      create_migration "14_step_past_the_end2.exs"
      assert run(TestRepo, path, :up, step: 3, log: false) == [13, 14]
    end
  end

  test "version migrations stop before all have been run" do
    in_tmp fn path ->
      create_migration "13_version_premature_end1.exs"
      create_migration "14_version_premature_end2.exs"
      assert run(TestRepo, path, :up, to: 13, log: false) == [13]
    end
  end

  test "version migrations stop at the number of available migrations" do
    in_tmp fn path ->
      create_migration "13_version_to_the_end1.exs"
      create_migration "14_version_to_the_end2.exs"
      assert run(TestRepo, path, :up, to: 14, log: false) == [13, 14]
    end
  end

  test "version migrations stop even if asked to exceed available" do
    in_tmp fn path ->
      create_migration "13_version_past_the_end1.exs"
      create_migration "14_version_past_the_end2.exs"
      assert run(TestRepo, path, :up, to: 15, log: false) == [13, 14]
    end
  end

  test "version migrations work iside directories" do
    in_tmp fn path ->
      File.mkdir_p!("foo")
      create_migration "foo/13_version_in_dir.exs"
      assert run(TestRepo, Path.join(path, "foo"), :up, to: 15, log: false) == [13]
    end
  end

  test "migrations run inside a transaction if the adapter supports ddl transactions" do
    capture_log fn ->
      Process.put(:supports_ddl_transaction?, true)
      up(TestRepo, 0, ChangeMigration)
      assert_receive {:transaction, _}
    end
  end

  test "migrations can be forced to run outside a transaction" do
    capture_log fn ->
      Process.put(:supports_ddl_transaction?, true)
      up(TestRepo, 0, NoTransactionMigration)
      refute_received {:transaction, _}
    end
  end

  test "migrations does not run inside a transaction if the adapter does not support ddl transactions" do
    capture_log fn ->
      Process.put(:supports_ddl_transaction?, false)
      up(TestRepo, 0, ChangeMigration)
      refute_received {:transaction, _}
    end
  end

  defp capture_log(fun) do
    ExUnit.CaptureIO.capture_io(:user, fn ->
      fun.()
      Logger.flush()
    end) |> String.strip
  end

  defp create_migration(name) do
    module = name |> Path.basename |> Path.rootname
    File.write! name, """
    defmodule Ecto.MigrationTest.S#{module} do
      use Ecto.Migration

      def up do
        execute "up"
      end

      def down do
        execute "down"
      end
    end
    """
  end
end
