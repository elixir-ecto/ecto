Code.require_file "../support/mock_repo.exs", __DIR__

defmodule Ecto.MigratorTest do
  use ExUnit.Case

  import Support.FileHelpers
  import Ecto.Migrator
  alias Ecto.MockRepo

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

  setup do
    Process.put(:migrated_versions, [1, 2, 3])
    :ok
  end

  test "logs migrations" do
    output = capture_log fn ->
      :ok = up(MockRepo, 0, ChangeMigration)
    end

    assert output =~ "== Running Ecto.MigratorTest.ChangeMigration.change/0 forward"
    assert output =~ "create table posts"
    assert output =~ "create index posts_title_index"
    assert output =~ ~r"== Migrated in \d.\ds"

    output = capture_log fn ->
      :ok = down(MockRepo, 0, ChangeMigration)
    end

    assert output =~ "== Running Ecto.MigratorTest.ChangeMigration.change/0 backward"
    assert output =~ "drop table posts"
    assert output =~ "drop index posts_title_index"
    assert output =~ ~r"== Migrated in \d.\ds"

    output = capture_log fn ->
      :ok = up(MockRepo, 0, UpDownMigration)
    end

    assert output =~ "== Running Ecto.MigratorTest.UpDownMigration.up/0 forward"
    assert output =~ "alter table posts"
    assert output =~ ~r"== Migrated in \d.\ds"

    output = capture_log fn ->
      :ok = down(MockRepo, 0, UpDownMigration)
    end

    assert output =~ "== Running Ecto.MigratorTest.UpDownMigration.down/0 forward"
    assert output =~ "execute \"foo\""
    assert output =~ ~r"== Migrated in \d.\ds"
  end

  test "up invokes the repository adapter with up commands" do
    assert up(MockRepo, 0, Migration, log: false) == :ok
    assert up(MockRepo, 1, Migration, log: false) == :already_up
    assert up(MockRepo, 10, ChangeMigration, log: false) == :ok
  end

  test "down invokes the repository adapter with down commands" do
    assert down(MockRepo, 0, Migration, log: false) == :already_down
    assert down(MockRepo, 1, Migration, log: false) == :ok
    assert down(MockRepo, 2, ChangeMigration, log: false) == :ok
  end

  test "up raises error when missing up/0 and change/0" do
    assert_raise Ecto.MigrationError, fn ->
      Ecto.Migrator.up(MockRepo, 0, InvalidMigration, log: false)
    end
  end

  test "down raises error when missing down/0 and change/0" do
    assert_raise Ecto.MigrationError, fn ->
      Ecto.Migrator.down(MockRepo, 1, InvalidMigration, log: false)
    end
  end

  test "expects files starting with an integer" do
    in_tmp fn path ->
      create_migration "a_sample.exs"
      assert run(MockRepo, path, :up, all: true, log: false) == []
    end
  end

  test "fails if there is no migration in file" do
    in_tmp fn path ->
      File.write! "13_sample.exs", ":ok"
      assert_raise Ecto.MigrationError, "file 13_sample.exs does not contain any Ecto.Migration", fn ->
        run(MockRepo, path, :up, all: true, log: false)
      end
    end
  end

  test "fails if there are duplicated versions" do
    in_tmp fn path ->
      create_migration "13_hello.exs"
      create_migration "13_other.exs"
      assert_raise Ecto.MigrationError, "migrations can't be executed, version 13 is duplicated", fn ->
        run(MockRepo, path, :up, all: true, log: false)
      end
    end
  end

  test "upwards migrations skips migrations that are already up" do
    in_tmp fn path ->
      create_migration "1_sample.exs"
      assert run(MockRepo, path, :up, all: true, log: false) == []
    end
  end

  test "downwards migrations skips migrations that are already down" do
    in_tmp fn path ->
      create_migration "1_sample.exs"
      create_migration "4_sample.exs"
      assert run(MockRepo, path, :down, all: true, log: false) == [1]
    end
  end

  test "stepwise migrations stop before all have been run" do
    in_tmp fn path ->
      create_migration "13_step_premature_end.exs"
      create_migration "14_step_premature_end.exs"
      assert run(MockRepo, path, :up, step: 1, log: false) == [13]
    end
  end

  test "stepwise migrations stop at the number of available migrations" do
    in_tmp fn path ->
      create_migration "13_step_to_the_end.exs"
      create_migration "14_step_to_the_end.exs"
      assert run(MockRepo, path, :up, step: 2, log: false) == [13, 14]
    end
  end

  test "stepwise migrations stop even if asked to exceed available" do
    in_tmp fn path ->
      create_migration "13_step_past_the_end.exs"
      create_migration "14_step_past_the_end.exs"
      assert run(MockRepo, path, :up, step: 3, log: false) == [13, 14]
    end
  end

  test "version migrations stop before all have been run" do
    in_tmp fn path ->
      create_migration "13_version_premature_end.exs"
      create_migration "14_version_premature_end.exs"
      assert run(MockRepo, path, :up, to: 13, log: false) == [13]
    end
  end

  test "version migrations stop at the number of available migrations" do
    in_tmp fn path ->
      create_migration "13_version_to_the_end.exs"
      create_migration "14_version_to_the_end.exs"
      assert run(MockRepo, path, :up, to: 14, log: false) == [13, 14]
    end
  end

  test "version migrations stop even if asked to exceed available" do
    in_tmp fn path ->
      create_migration "13_version_past_the_end.exs"
      create_migration "14_version_past_the_end.exs"
      assert run(MockRepo, path, :up, to: 15, log: false) == [13, 14]
    end
  end

  test "the migration can be disabled" do
    capture_log fn ->
      up(MockRepo, 0, NoTransactionMigration)

      # Assert there's only one transaction message, which is for when the
      # SchemaMigration does his thing. If @disable_ddl_transaction was set to
      # false, we would have *two* {:transaction, _} messages.
      {:messages, messages} = Process.info(self, :messages)
      assert [{:transaction, _}] = messages
    end
  end

  defp capture_log(fun) do
    ExUnit.CaptureIO.capture_io(:user, fn ->
      fun.()
      Logger.flush()
    end) |> String.strip
  end

  defp create_migration(name) do
    File.write! name, """
    defmodule Ecto.MigrationTest.S#{Path.rootname(name)} do
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
