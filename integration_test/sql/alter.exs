defmodule Ecto.Integration.AlterTest do
  use Ecto.Integration.Case, async: false

  alias Ecto.Integration.PoolRepo

  defmodule AlterMigrationOne do
    use Ecto.Migration

    def up do
      create table(:alter_col_type) do
        add :value, :integer
      end

      execute "INSERT INTO alter_col_type (value) VALUES (1)"
    end

    def down do
      drop table(:alter_col_type)
    end
  end

  defmodule AlterMigrationTwo do
    use Ecto.Migration

    def up do
      alter table(:alter_col_type) do
        modify :value, :numeric
      end
    end

    def down do
      alter table(:alter_col_type) do
        modify :value, :integer
      end
    end
  end

  import Ecto.Query, only: [from: 1, from: 2]
  import Ecto.Migrator, only: [up: 4, down: 4]

  test "reset cache on returning query after alter column type" do
    values = from v in "alter_col_type", select: v.value

    assert :ok == up(PoolRepo, 20161112120000, AlterMigrationOne, log: false)
    assert PoolRepo.all(values) == [1]

    assert :ok == up(PoolRepo, 20161112130000, AlterMigrationTwo, log: false)
    assert_raise ArgumentError, ~r"stale type",
      fn() -> PoolRepo.all(values) end

    PoolRepo.transaction(fn() ->
      assert [%Decimal{}] = PoolRepo.all(values)

      assert :ok == down(PoolRepo, 20161112130000, AlterMigrationTwo, log: false)
      catch_error PoolRepo.all(values, [mode: :savepoint])
      assert PoolRepo.all(values) == [1]
    end)

  after
    assert :ok == down(PoolRepo, 20161112120000, AlterMigrationOne, log: false)
  end

  test "reset cache on paramterised query after alter column type" do
    values = from v in "alter_col_type"

    assert :ok == up(PoolRepo, 20161112120000, AlterMigrationOne, log: false)
    assert PoolRepo.update_all(values, [set: [value: 2]]) == {1, nil}

    assert :ok == up(PoolRepo, 20161112130000, AlterMigrationTwo, log: false)
    assert_raise ArgumentError, ~r"stale type information",
      fn() -> PoolRepo.update_all(values, [set: [value: 3]]) end

    PoolRepo.transaction(fn() ->
      assert PoolRepo.update_all(values, [set: [value: Decimal.new(3)]]) == {1, nil}

      assert :ok == down(PoolRepo, 20161112130000, AlterMigrationTwo, log: false)
      
      assert PoolRepo.update_all(values, [set: [value: 4]]) == {1, nil}
    end)

  after
    assert :ok == down(PoolRepo, 20161112120000, AlterMigrationOne, log: false)
  end
end
