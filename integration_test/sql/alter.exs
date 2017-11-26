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

  defmodule AlterMigrationThree do
    use Ecto.Migration

    def up do
      alter table(:alter_col_type) do
        remove :value
        add :value, :timestamp
      end
    end

    def down do
      alter table(:alter_col_type) do
        remove :value
        add :value, :numeric
      end
    end
  end

  import Ecto.Query, only: [from: 1, from: 2]

  defp run(direction, repo, module) do
    Ecto.Migration.Runner.run(repo, module, :forward, direction, direction, log: false)
  end

  test "reset cache on returning query after alter column type" do
    values = from v in "alter_col_type", select: v.value

    assert :ok == run(:up, PoolRepo, AlterMigrationOne)
    assert PoolRepo.all(values) == [1]

    assert :ok == run(:up, PoolRepo, AlterMigrationTwo)

    assert [%Decimal{}] = PoolRepo.all(values)

    PoolRepo.transaction(fn() ->
      assert [%Decimal{}] = PoolRepo.all(values)

      assert :ok == run(:down, PoolRepo, AlterMigrationTwo)

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
    assert :ok == run(:down, PoolRepo, AlterMigrationOne)
  end

  test "reset cache on compatible paramterised query after alter column type" do
    values = from v in "alter_col_type"

    assert :ok == run(:up, PoolRepo, AlterMigrationOne)
    assert PoolRepo.update_all(values, [set: [value: 2]]) == {1, nil}

    assert :ok == run(:up, PoolRepo, AlterMigrationTwo)

    # Should always succeed with old parameter type
    for val <- 3..6 do
      assert PoolRepo.update_all(values, [set: [value: val]]) == {1, nil}
    end

    # optionally fail once with ArgumentError when first encounter new type
    try do
      PoolRepo.update_all(values, [set: [value: Decimal.new(7)]])
    rescue
      ArgumentError ->
        :ok
    else
      result ->
        assert result == {1, nil}
    end

    PoolRepo.transaction(fn() ->
      assert PoolRepo.update_all(values, [set: [value: Decimal.new(8)]]) == {1, nil}

      assert :ok == run(:down, PoolRepo, AlterMigrationTwo)

      assert PoolRepo.update_all(values, [set: [value: 9]]) == {1, nil}
    end)
  after
    assert :ok == run(:down, PoolRepo, AlterMigrationOne)
  end

  test "reset cache on incompatible paramterised query after alter column type" do
    values = from v in "alter_col_type"

    assert :ok == run(:up, PoolRepo, AlterMigrationOne)
    assert PoolRepo.update_all(values, [set: [value: 2]]) == {1, nil}

    assert :ok == run(:up, PoolRepo, AlterMigrationTwo)
    assert :ok == run(:up, PoolRepo, AlterMigrationThree)

    # Should always fail with old parameter type
    try do
      PoolRepo.update_all(values, [set: [value: 3]])
    catch
      :error, _ ->
        :ok
    end

    PoolRepo.transaction(fn() ->
      assert PoolRepo.update_all(values, [set: [value: NaiveDateTime.utc_now()]]) == {1, nil}

      assert :ok == run(:down, PoolRepo, AlterMigrationThree)
      assert :ok == run(:down, PoolRepo, AlterMigrationTwo)

      # optionally fail once with ArgumentError when first encounter new type
      try do
        PoolRepo.update_all(values, [set: [value: 4]])
      rescue
        ArgumentError ->
          :ok
      else
        result ->
          assert result == {1, nil}
      end

      assert PoolRepo.update_all(values, [set: [value: 5]]) == {1, nil}
    end)
  after
    assert :ok == run(:down, PoolRepo, AlterMigrationOne)
  end
end
