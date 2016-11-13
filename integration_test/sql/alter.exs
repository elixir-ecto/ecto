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

    # optionally fail once with ArgumentError when preparing query prepared on
    # another connection (and clear cache)
    try do
      PoolRepo.all(values)
    rescue
      err in [ArgumentError] ->
        assert Exception.message(err) =~ "stale type"
        assert [%Decimal{}] = PoolRepo.all(values)
    else
      result ->
        assert [%Decimal{}] = result
    end

    PoolRepo.transaction(fn() ->
      assert [%Decimal{}] = PoolRepo.all(values)

      assert :ok == down(PoolRepo, 20161112130000, AlterMigrationTwo, log: false)

      # optionally fail once with database error when already prepared on
      # connection (and clear cache)
      try do
        PoolRepo.all(values, [mode: :savepoint])
      catch
        :error, _ ->
          assert PoolRepo.all(values) == [1]
      else
        result ->
          assert result == [1]
      end
    end)

  after
    assert :ok == down(PoolRepo, 20161112120000, AlterMigrationOne, log: false)
  end

  test "reset cache on paramterised query after alter column type" do
    values = from v in "alter_col_type"

    assert :ok == up(PoolRepo, 20161112120000, AlterMigrationOne, log: false)
    assert PoolRepo.update_all(values, [set: [value: 2]]) == {1, nil}

    assert :ok == up(PoolRepo, 20161112130000, AlterMigrationTwo, log: false)

    # optionally fail once with ArgumentError when preparing query prepared on
    # another connection (and clear cache)
    try do
      PoolRepo.update_all(values, [set: [value: 3]])
    rescue
      err in [ArgumentError] ->
        assert Exception.message(err) =~ "stale type"
        assert PoolRepo.update_all(values, [set: [value: 4]]) == {1, nil}
    else
      result ->
        assert result == {1, nil}
    end

    PoolRepo.transaction(fn() ->
      assert PoolRepo.update_all(values, [set: [value: Decimal.new(5)]]) == {1, nil}

      assert :ok == down(PoolRepo, 20161112130000, AlterMigrationTwo, log: false)

      assert PoolRepo.update_all(values, [set: [value: 6]]) == {1, nil}
    end)

  after
    assert :ok == down(PoolRepo, 20161112120000, AlterMigrationOne, log: false)
  end
end
