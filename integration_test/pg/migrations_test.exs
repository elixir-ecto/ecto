defmodule Ecto.Integration.MigrationsTest do
  use ExUnit.Case, async: true

  import Ecto.Migrator, only: [up: 4]
  alias Ecto.Integration.PoolRepo

  # Avoid migration out of order warnings
  @moduletag :capture_log
  @base_migration 3_000_000

  defmodule DuplicateTableMigration do
    use Ecto.Migration

    def change do
      create_if_not_exists table(:duplicate_table)
      create_if_not_exists table(:duplicate_table)
    end
  end

  test "logs Postgres notice messages" do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        num = @base_migration + System.unique_integer([:positive])
        up(PoolRepo, num, DuplicateTableMigration, log: false)
      end)

    assert log =~ ~s(relation "duplicate_table" already exists, skipping)
  end
end
