defmodule Ecto.Integration.MigrationsTest do
  # Cannot be async as other tests may migrate
  use ExUnit.Case

  import Ecto.Migrator, only: [up: 4]

  alias Ecto.Integration.PoolRepo

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
        up(PoolRepo, 20040906120002, DuplicateTableMigration, log: false)
      end)

    assert log =~ ~s(relation "duplicate_table" already exists, skipping)
  end
end
